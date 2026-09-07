//! Fish shell integration: plugin/theme generation, diagnostics and `conf.d`
//! installation.
//!
//! The fish plugin mirrors the zsh plugin one to one: an Enter-key binding
//! intercepts `:` lines, state lives in per-session global variables, and
//! every Forge call goes through the same flags and environment variables
//! the zsh plugin uses.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::CommandFactory;
use clap_complete::generate;
use clap_complete::shells::Fish;
use include_dir::{Dir, include_dir};

use super::setup::{ShellSetupResult, backup_file, run_script};
use super::{Shell, normalize_script, strip_comments};
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
/// Returns an error if the doctor script cannot be executed or reports
/// failures.
pub fn run_fish_doctor() -> Result<()> {
    let script_content = include_str!("../../../../shell-plugin/fish/doctor.fish");
    run_script(Shell::Fish, script_content, "doctor")
}

/// Shows fish keyboard shortcuts with streaming output.
///
/// # Errors
///
/// Returns an error if the keyboard script cannot be executed.
pub fn run_fish_keyboard() -> Result<()> {
    let script_content = include_str!("../../../../shell-plugin/fish/keyboard.fish");
    run_script(Shell::Fish, script_content, "keyboard")
}

/// Resolves the path of the Forge `conf.d` snippet:
/// `$XDG_CONFIG_HOME/fish/conf.d/forge.fish`, falling back to
/// `~/.config/fish/conf.d/forge.fish`.
///
/// # Errors
///
/// Returns an error when neither `XDG_CONFIG_HOME` nor `HOME` is set.
fn fish_conf_path() -> Result<PathBuf> {
    let config_home = match std::env::var("XDG_CONFIG_HOME") {
        Ok(dir) if !dir.trim().is_empty() => PathBuf::from(dir),
        _ => {
            let home = std::env::var("HOME").context("HOME environment variable not set")?;
            PathBuf::from(home).join(".config")
        }
    };
    Ok(config_home.join("fish").join("conf.d").join("forge.fish"))
}

/// Renders the `conf.d` snippet, inserting the optional nerd font and editor
/// settings right after the managed header so they apply to every fish
/// process (the plugin itself only loads in interactive shells).
fn render_fish_setup(disable_nerd_font: bool, forge_editor: Option<&str>) -> String {
    let template = normalize_script(include_str!(
        "../../../../shell-plugin/fish/forge.setup.fish"
    ));

    let mut settings: Vec<String> = Vec::new();
    if disable_nerd_font {
        settings.push(
            "# Disable Nerd Fonts (set during setup - icons not displaying correctly)".to_string(),
        );
        settings.push("# To re-enable: remove this line and install a Nerd Font from https://www.nerdfonts.com/".to_string());
        settings.push("set -gx NERD_FONT 0".to_string());
        settings.push(String::new());
    }
    if let Some(editor) = forge_editor {
        settings.push("# Editor for editing prompts (set during setup)".to_string());
        settings.push("# To change: update FORGE_EDITOR or remove to use $EDITOR".to_string());
        settings.push(format!("set -gx FORGE_EDITOR {}", fish_quote(editor)));
        settings.push(String::new());
    }

    if settings.is_empty() {
        return template;
    }

    // The managed header ends at the first blank line
    match template.split_once("\n\n") {
        Some((header, rest)) => format!("{header}\n\n{}\n{rest}", settings.join("\n")),
        None => format!("{}\n{template}", settings.join("\n")),
    }
}

/// Sets up fish integration by writing the Forge `conf.d` snippet.
///
/// # Arguments
///
/// * `disable_nerd_font` - If true, exports `NERD_FONT=0` from the snippet
/// * `forge_editor` - If Some(editor), exports `FORGE_EDITOR` from the snippet
///
/// # Errors
///
/// Returns an error if the configuration directory cannot be resolved or the
/// snippet cannot be written.
pub fn setup_fish_integration(
    disable_nerd_font: bool,
    forge_editor: Option<&str>,
) -> Result<ShellSetupResult> {
    let conf_path = fish_conf_path()?;
    setup_fish_integration_at(&conf_path, disable_nerd_font, forge_editor)
}

/// Writes the `conf.d` snippet to `conf_path`, backing up a differing
/// existing file first.
///
/// # Errors
///
/// Returns an error if the file cannot be read, backed up or written.
fn setup_fish_integration_at(
    conf_path: &Path,
    disable_nerd_font: bool,
    forge_editor: Option<&str>,
) -> Result<ShellSetupResult> {
    let content = render_fish_setup(disable_nerd_font, forge_editor);

    let existing = if conf_path.exists() {
        Some(
            fs::read_to_string(conf_path)
                .context(format!("Failed to read {}", conf_path.display()))?,
        )
    } else {
        None
    };

    let (action, backup_path) = match existing.as_deref() {
        None => ("added", None),
        Some(old) if old == content => ("unchanged", None),
        Some(_) => ("updated", Some(backup_file(conf_path)?)),
    };

    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent).context(format!("Failed to create {}", parent.display()))?;
    }
    fs::write(conf_path, &content)
        .context(format!("Failed to write to {}", conf_path.display()))?;

    Ok(ShellSetupResult { message: format!("forge plugins {action}"), backup_path })
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
    fn test_generated_plugin_binds_enter_and_tab_widgets() {
        let fixture = generate_fish_plugin().unwrap();

        let actual = fixture.contains("function __forge_accept_line")
            && fixture.contains("function __forge_complete")
            && fixture.contains("bind -M $mode enter __forge_accept_line")
            && fixture.contains("bind -M $mode tab __forge_complete")
            && fixture.contains("bind -M $mode \\r __forge_accept_line")
            && fixture.contains("function __forge_context_postexec --on-event fish_postexec");
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
    fn test_render_fish_setup_without_settings_is_the_template() {
        let actual = render_fish_setup(false, None);

        let actual = actual.starts_with("# !! This file is managed by 'forge fish setup' !!")
            && actual.contains("status is-interactive; or exit")
            && actual.contains("$__forge_bin fish plugin | source")
            && actual.contains("$__forge_bin fish theme | source")
            && !actual.contains("NERD_FONT")
            && !actual.contains("FORGE_EDITOR");
        let expected = true;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_render_fish_setup_inserts_settings_after_header() {
        let fixture = render_fish_setup(true, Some("code --wait"));

        let header_end = fixture.find("\n\n").unwrap();
        let settings_pos = fixture.find("set -gx NERD_FONT 0").unwrap();
        let editor_pos = fixture.find("set -gx FORGE_EDITOR 'code --wait'").unwrap();
        let guard_pos = fixture.find("status is-interactive; or exit").unwrap();

        let actual =
            header_end < settings_pos && settings_pos < editor_pos && editor_pos < guard_pos;
        let expected = true;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_setup_fish_integration_at_creates_updates_and_backs_up() {
        let temp_dir = tempfile::TempDir::new().unwrap();
        let conf_path = temp_dir
            .path()
            .join("fish")
            .join("conf.d")
            .join("forge.fish");

        let first = setup_fish_integration_at(&conf_path, false, None).unwrap();
        let unchanged = setup_fish_integration_at(&conf_path, false, None).unwrap();
        let updated = setup_fish_integration_at(&conf_path, true, Some("vim")).unwrap();

        let backups = fs::read_dir(conf_path.parent().unwrap())
            .unwrap()
            .filter_map(|entry| entry.ok())
            .filter(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with("forge.fish.bak.")
            })
            .count();
        let content = fs::read_to_string(&conf_path).unwrap();

        let actual = (
            first.message,
            first.backup_path.is_none(),
            unchanged.message,
            unchanged.backup_path.is_none(),
            updated.message,
            updated.backup_path.is_some(),
            backups,
            content.contains("set -gx FORGE_EDITOR 'vim'")
                && content.contains("set -gx NERD_FONT 0"),
        );
        let expected = (
            "forge plugins added".to_string(),
            true,
            "forge plugins unchanged".to_string(),
            true,
            "forge plugins updated".to_string(),
            true,
            1,
            true,
        );
        assert_eq!(actual, expected);
    }

    /// The doctor script runs `fish` directly; accept the cases where fish is
    /// missing (CI) or the environment fails some checks.
    #[test]
    fn test_run_fish_doctor_streaming() {
        let actual = run_fish_doctor();

        let actual = match actual {
            Ok(_) => true,
            Err(e) => {
                let message = e.to_string();
                message.contains("exit code") || message.contains("Failed to execute")
            }
        };
        let expected = true;
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
