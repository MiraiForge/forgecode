//! Fish shell integration: plugin/theme generation, diagnostics and `conf.d`
//! installation.
//!
//! The fish plugin mirrors the zsh plugin one to one: an Enter-key binding
//! intercepts `:` lines, state lives in per-session global variables, and
//! every Forge call goes through the same flags and environment variables
//! the zsh plugin uses.

use anyhow::Result;
use clap::CommandFactory;
use clap_complete::generate;
use clap_complete::shells::Fish;
use include_dir::{Dir, include_dir};

use super::setup::ShellSetupResult;
use super::{normalize_script, strip_comments};
use crate::cli::Cli;
use crate::model::shell_command_names;

/// Embeds shell plugin files for fish integration
static FISH_PLUGIN_LIB: Dir<'static> =
    include_dir!("$CARGO_MANIFEST_DIR/../../shell-plugin/fish/lib");

/// Generates the complete fish plugin by combining embedded files, command
/// stubs and clap completions.
///
/// The output is meant to be piped into `source`:
/// `forge fish plugin | source`.
///
/// # Errors
///
/// Returns an error when an embedded file or the generated completions are
/// not valid UTF-8.
pub fn generate_fish_plugin() -> Result<String> {
    let mut output = String::new();

    // Embedded files contain only definitions (functions and `set -g`
    // defaults) so their concatenation order does not matter; `__forge_init`
    // wires bindings and hooks once everything is defined.
    for file in forge_embed::files(&FISH_PLUGIN_LIB) {
        let content = normalize_script(std::str::from_utf8(file.contents())?);
        output.push_str(&strip_comments(&content));
    }

    // Fish has no user-defined syntax highlighter; a `:` line is coloured as
    // an unknown command unless a function of that name exists. The stubs
    // make `:`, `:sage`, `:commit` … highlight as valid commands and provide
    // a fallback dispatch path when the Enter binding is bypassed.
    output.push_str("\n# --- Command stubs ---\n");
    output.push_str(&command_stubs());

    // Generate clap completions for the CLI
    let mut cmd = Cli::command();
    let mut completions = Vec::new();
    generate(Fish, &mut cmd, "forge", &mut completions);

    let completions_str = String::from_utf8(completions)?;
    output.push_str("\n# --- Clap Completions ---\n");
    output.push_str(&completions_str);

    // Apply bindings and hooks, then mark the plugin as loaded (with timestamp)
    output.push_str("\nfunctions -q __forge_init; and __forge_init\n");
    output.push_str("set -g _FORGE_PLUGIN_LOADED (date +%s)\n");

    Ok(output)
}

/// Generates the fish theme (right prompt) for Forge.
///
/// # Errors
///
/// Returns an error when the embedded theme cannot be read.
pub fn generate_fish_theme() -> Result<String> {
    let mut content = normalize_script(include_str!(
        "../../../../shell-plugin/fish/forge.theme.fish"
    ));

    // Set variable to indicate theme is loaded (with timestamp)
    content.push_str("\nset -g _FORGE_THEME_LOADED (date +%s)\n");

    Ok(content)
}

/// Runs diagnostics on the fish shell environment with streaming output.
///
/// # Errors
///
/// Returns an error until the fish doctor script ships.
pub fn run_fish_doctor() -> Result<()> {
    anyhow::bail!("`forge fish doctor` is not available yet")
}

/// Shows fish keyboard shortcuts with streaming output.
///
/// # Errors
///
/// Returns an error until the fish keyboard script ships.
pub fn run_fish_keyboard() -> Result<()> {
    anyhow::bail!("`forge fish keyboard` is not available yet")
}

/// Sets up fish integration by writing the Forge `conf.d` snippet.
///
/// # Errors
///
/// Returns an error until the fish setup snippet ships.
pub fn setup_fish_integration(
    _disable_nerd_font: bool,
    _forge_editor: Option<&str>,
) -> Result<ShellSetupResult> {
    anyhow::bail!("`forge fish setup` is not available yet")
}

/// Renders `function :<name>` stubs for every built-in command and alias.
fn command_stubs() -> String {
    let mut output = String::new();
    output.push_str(&stub("", "Forge: send a prompt to the active agent"));
    for (name, usage) in shell_command_names() {
        output.push_str(&stub(&name, &format!("Forge: {usage}")));
    }
    output
}

/// Renders a single stub function that forwards to the plugin dispatcher.
fn stub(name: &str, description: &str) -> String {
    format!(
        "function :{name} --description {desc}\n    \
         if functions -q __forge_dispatch_argv\n        \
         __forge_dispatch_argv {name_arg} $argv\n    \
         else\n        \
         echo 'forge: shell plugin is not fully loaded; run: forge fish plugin | source' >&2\n        \
         return 1\n    \
         end\n\
         end\n",
        desc = fish_quote(description),
        name_arg = fish_quote(name),
    )
}

/// Quotes `text` as a fish single-quoted string.
///
/// Inside single quotes fish only recognises `\'` and `\\` as escapes.
fn fish_quote(text: &str) -> String {
    let escaped = text.replace('\\', "\\\\").replace('\'', "\\'");
    format!("'{escaped}'")
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;

    #[test]
    fn test_fish_quote_escapes_quotes_and_backslashes() {
        let actual = fish_quote("it's a \\ test");
        let expected = "'it\\'s a \\\\ test'";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_stub_forwards_to_dispatcher() {
        let actual = stub("sage", "Forge: research");
        let expected = "function :sage --description 'Forge: research'\n    if functions -q __forge_dispatch_argv\n        __forge_dispatch_argv 'sage' $argv\n    else\n        echo 'forge: shell plugin is not fully loaded; run: forge fish plugin | source' >&2\n        return 1\n    end\nend\n";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_generated_plugin_contains_stubs_completions_and_loaded_marker() {
        let fixture = generate_fish_plugin().unwrap();

        let actual = fixture.contains("function : --description")
            && fixture.contains("function :sage --description")
            && fixture.contains("function :commit-preview --description")
            && fixture.contains("function :ask --description")
            && fixture.contains("complete -c forge")
            && fixture.contains("functions -q __forge_init; and __forge_init\n")
            && fixture.ends_with("set -g _FORGE_PLUGIN_LOADED (date +%s)\n");
        let expected = true;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_generated_plugin_has_no_comment_lines_before_completions() {
        let fixture = generate_fish_plugin().unwrap();
        let body = fixture.split("# --- Command stubs ---").next().unwrap();

        let actual = body.lines().any(|line| line.trim_start().starts_with('#'));
        let expected = false;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_generated_theme_sets_loaded_marker() {
        let fixture = generate_fish_theme().unwrap();

        let actual = fixture.contains("function fish_right_prompt")
            && fixture.ends_with("set -g _FORGE_THEME_LOADED (date +%s)\n");
        let expected = true;
        assert_eq!(actual, expected);
    }
}
