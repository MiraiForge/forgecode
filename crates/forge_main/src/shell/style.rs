//! Prompt styling utilities.
//!
//! Zsh prompts are rendered by zsh's own prompt engine and need `%F{n}`-style
//! prompt escapes, which work correctly in `PROMPT` and `RPROMPT` contexts.
//! Fish prints the output of `fish_right_prompt` verbatim and needs raw ANSI
//! SGR sequences instead. [`Styled`] renders the same colour and weight for
//! whichever [`Shell`] is requested.

use std::fmt::{self, Display};

use super::Shell;

/// Prompt colour using the 256-colour palette.
///
/// Maps to zsh's `%F{N}` prompt escape or the ANSI `38;5;N` SGR parameter.
#[derive(Debug, Clone, Copy)]
pub struct PromptColor(u8);

impl PromptColor {
    /// White (color 15)
    pub const WHITE: Self = Self(15);
    /// Cyan (color 134)
    pub const CYAN: Self = Self(134);
    /// Green (color 2)
    pub const GREEN: Self = Self(2);
    /// Yellow (color 3)
    pub const YELLOW: Self = Self(3);
    /// Dimmed gray (color 240)
    pub const DIMMED: Self = Self(240);

    /// Creates a color from a 256-color palette value.
    #[cfg(test)]
    pub const fn new(value: u8) -> Self {
        Self(value)
    }
}

impl Display for PromptColor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A styled string for shell prompts.
///
/// Wraps text with the escape sequences the target shell's prompt renderer
/// understands.
#[derive(Debug, Clone)]
pub struct Styled<'a> {
    text: &'a str,
    fg: Option<PromptColor>,
    bold: bool,
    shell: Shell,
}

impl<'a> Styled<'a> {
    /// Creates a new styled string with the given text for `shell`.
    pub fn new(text: &'a str, shell: Shell) -> Self {
        Self { text, fg: None, bold: false, shell }
    }

    /// Sets the foreground color.
    pub fn fg(mut self, color: PromptColor) -> Self {
        self.fg = Some(color);
        self
    }

    /// Makes the text bold.
    pub fn bold(mut self) -> Self {
        self.bold = true;
        self
    }
}

impl Display for Styled<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.shell {
            Shell::Zsh => {
                if self.bold {
                    write!(f, "%B")?;
                }
                if let Some(ref color) = self.fg {
                    write!(f, "%F{{{}}}", color)?;
                }
                write!(f, "{}", self.text)?;
                if self.fg.is_some() {
                    write!(f, "%f")?;
                }
                if self.bold {
                    write!(f, "%b")?;
                }
            }
            Shell::Fish => {
                if self.bold {
                    write!(f, "\x1b[1m")?;
                }
                if let Some(ref color) = self.fg {
                    write!(f, "\x1b[38;5;{}m", color)?;
                }
                write!(f, "{}", self.text)?;
                // Reset only what was set, mirroring zsh's `%f` / `%b`, so
                // surrounding styles applied by the user's prompt survive.
                if self.fg.is_some() {
                    write!(f, "\x1b[39m")?;
                }
                if self.bold {
                    write!(f, "\x1b[22m")?;
                }
            }
        }

        Ok(())
    }
}

/// Extension trait for styling strings for shell prompts.
pub trait PromptStyle {
    /// Creates a styled wrapper for this string targeting `shell`.
    fn styled(&self, shell: Shell) -> Styled<'_>;
}

impl PromptStyle for str {
    fn styled(&self, shell: Shell) -> Styled<'_> {
        Styled::new(self, shell)
    }
}

impl PromptStyle for String {
    fn styled(&self, shell: Shell) -> Styled<'_> {
        Styled::new(self.as_str(), shell)
    }
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;

    #[test]
    fn test_plain_text() {
        let actual = "hello".styled(Shell::Zsh).to_string();
        let expected = "hello";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_bold() {
        let actual = "hello".styled(Shell::Zsh).bold().to_string();
        let expected = "%Bhello%b";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_bold_and_color() {
        let actual = "hello"
            .styled(Shell::Zsh)
            .bold()
            .fg(PromptColor::WHITE)
            .to_string();
        let expected = "%B%F{15}hello%f%b";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_fixed_color() {
        let actual = "hello"
            .styled(Shell::Zsh)
            .fg(PromptColor::new(240))
            .to_string();
        let expected = "%F{240}hello%f";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_fish_plain_text() {
        let actual = "hello".styled(Shell::Fish).to_string();
        let expected = "hello";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_fish_bold_and_color() {
        let actual = "hello"
            .styled(Shell::Fish)
            .bold()
            .fg(PromptColor::WHITE)
            .to_string();
        let expected = "\x1b[1m\x1b[38;5;15mhello\x1b[39m\x1b[22m";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_fish_fixed_color() {
        let actual = "hello"
            .styled(Shell::Fish)
            .fg(PromptColor::new(240))
            .to_string();
        let expected = "\x1b[38;5;240mhello\x1b[39m";
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_styled_dispatches_on_shell() {
        let actual = "hi".styled(Shell::Fish).bold().to_string();
        let expected = "\x1b[1mhi\x1b[22m";
        assert_eq!(actual, expected);
    }
}
