//! Shell integration for zsh and fish.
//!
//! This module provides all shell-related functionality including:
//! - Plugin generation and installation
//! - Theme generation
//! - Shell diagnostics
//! - Right prompt (rprompt) display
//! - Prompt styling utilities
//!
//! Every shell shares the same contract with the rest of Forge: session state
//! travels through environment variables and CLI flags, and Forge renders
//! shell-specific output (prompt escapes, completions, setup snippets) based
//! on the [`Shell`] the caller asks for.

use std::path::Path;

use clap::ValueEnum;

mod fish;
pub(crate) mod paste;
mod rprompt;
mod setup;
mod style;
mod zsh;

/// Shells that Forge can generate an integration for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Shell {
    /// Z shell: plugin loaded from `.zshrc`, right prompt via `RPROMPT`.
    Zsh,
    /// Fish shell: plugin loaded from `conf.d`, right prompt via
    /// `fish_right_prompt`.
    Fish,
}

impl Shell {
    /// Detects the shell from a `$SHELL`-style path such as `/bin/zsh` or
    /// `/opt/homebrew/bin/fish`.
    ///
    /// Returns `None` when the basename is not a supported shell.
    pub fn from_shell_path(shell: &str) -> Option<Self> {
        let name = Path::new(shell).file_name()?.to_str()?;
        match name {
            "zsh" => Some(Self::Zsh),
            "fish" => Some(Self::Fish),
            _ => None,
        }
    }

    /// Lowercase shell name as used on the command line (`forge zsh …`).
    pub fn name(self) -> &'static str {
        match self {
            Self::Zsh => "zsh",
            Self::Fish => "fish",
        }
    }

    /// Human readable location of the file that `forge <shell> setup`
    /// writes.
    pub fn config_hint(self) -> &'static str {
        match self {
            Self::Zsh => "~/.zshrc",
            Self::Fish => "~/.config/fish/conf.d/forge.fish",
        }
    }

    /// Command the user runs to reload their shell after setup.
    pub fn reload_hint(self) -> &'static str {
        match self {
            Self::Zsh => "exec zsh",
            Self::Fish => "exec fish",
        }
    }
}

impl std::fmt::Display for Shell {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name())
    }
}

/// Normalizes shell script content for cross-platform compatibility.
///
/// Strips carriage returns (`\r`) that appear when `include_str!` or
/// `include_dir!` embed files on Windows (where `git core.autocrlf=true`
/// converts LF to CRLF on checkout). Neither zsh nor fish can parse `\r` in
/// scripts.
pub(crate) fn normalize_script(content: &str) -> String {
    content.replace("\r\n", "\n").replace('\r', "\n")
}

/// Strips comment and blank lines from an embedded plugin file so the
/// generated plugin stays small enough to `eval`/`source` quickly.
pub(crate) fn strip_comments(content: &str) -> String {
    let mut output = String::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if !trimmed.is_empty() && !trimmed.starts_with('#') {
            output.push_str(line);
            output.push('\n');
        }
    }
    output
}

/// Generates the plugin script for `shell`.
///
/// # Errors
///
/// Returns an error when an embedded file is not valid UTF-8.
pub fn generate_plugin(shell: Shell) -> anyhow::Result<String> {
    match shell {
        Shell::Zsh => zsh::generate_zsh_plugin(),
        Shell::Fish => fish::generate_fish_plugin(),
    }
}

/// Generates the prompt theme script for `shell`.
///
/// # Errors
///
/// Returns an error when the embedded theme cannot be read.
pub fn generate_theme(shell: Shell) -> anyhow::Result<String> {
    match shell {
        Shell::Zsh => zsh::generate_zsh_theme(),
        Shell::Fish => fish::generate_fish_theme(),
    }
}

/// Runs the diagnostics script for `shell`, streaming its output.
///
/// # Errors
///
/// Returns an error when the shell binary is missing or the script exits
/// with a non-zero status.
pub fn run_doctor(shell: Shell) -> anyhow::Result<()> {
    match shell {
        Shell::Zsh => zsh::run_zsh_doctor(),
        Shell::Fish => fish::run_fish_doctor(),
    }
}

/// Prints the keyboard shortcut reference for `shell`'s line editor.
///
/// # Errors
///
/// Returns an error when the shell binary is missing or the script exits
/// with a non-zero status.
pub fn run_keyboard(shell: Shell) -> anyhow::Result<()> {
    match shell {
        Shell::Zsh => zsh::run_zsh_keyboard(),
        Shell::Fish => fish::run_fish_keyboard(),
    }
}

/// Installs the integration for `shell` into the user's configuration.
///
/// # Arguments
///
/// * `disable_nerd_font` - When true the generated config exports
///   `NERD_FONT=0`.
/// * `forge_editor` - When set the generated config exports `FORGE_EDITOR`.
///
/// # Errors
///
/// Returns an error when the configuration file cannot be read or written.
pub fn setup_integration(
    shell: Shell,
    disable_nerd_font: bool,
    forge_editor: Option<&str>,
) -> anyhow::Result<setup::ShellSetupResult> {
    match shell {
        Shell::Zsh => zsh::setup_zsh_integration(disable_nerd_font, forge_editor),
        Shell::Fish => fish::setup_fish_integration(disable_nerd_font, forge_editor),
    }
}

pub use rprompt::RPrompt;

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;

    #[test]
    fn test_shell_from_shell_path_detects_basename() {
        let actual = [
            Shell::from_shell_path("/bin/zsh"),
            Shell::from_shell_path("/opt/homebrew/bin/fish"),
            Shell::from_shell_path("fish"),
            Shell::from_shell_path("/bin/bash"),
            Shell::from_shell_path(""),
        ];
        let expected = [
            Some(Shell::Zsh),
            Some(Shell::Fish),
            Some(Shell::Fish),
            None,
            None,
        ];
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_strip_comments_drops_blank_and_comment_lines() {
        let fixture =
            "#!/usr/bin/env fish\n\n# comment\nset -g x 1\n  # indented comment\necho done\n";
        let actual = strip_comments(fixture);
        let expected = "set -g x 1\necho done\n";
        assert_eq!(actual, expected);
    }
}
