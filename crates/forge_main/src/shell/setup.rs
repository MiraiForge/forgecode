//! Helpers shared by the zsh and fish installers and script runners.

use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::Stdio;

use anyhow::{Context, Result};

use super::Shell;

/// Result of a shell setup operation.
#[derive(Debug)]
pub struct ShellSetupResult {
    /// Status message describing what was done
    pub message: String,
    /// Path to backup file if one was created
    pub backup_path: Option<PathBuf>,
}

/// Represents the state of markers in a file.
pub(super) enum MarkerState {
    /// No markers found
    NotFound,
    /// Valid markers with correct positions
    Valid { start: usize, end: usize },
    /// Invalid markers (incorrect order or incomplete)
    Invalid {
        start: Option<usize>,
        end: Option<usize>,
    },
}

/// Parses the file content to find and validate marker positions.
///
/// # Arguments
///
/// * `lines` - The lines of the file to parse
/// * `start_marker` - The start marker to look for
/// * `end_marker` - The end marker to look for
pub(super) fn parse_markers(lines: &[String], start_marker: &str, end_marker: &str) -> MarkerState {
    let start_idx = lines.iter().position(|line| line.trim() == start_marker);
    let end_idx = lines.iter().position(|line| line.trim() == end_marker);

    match (start_idx, end_idx) {
        (Some(start), Some(end)) if start < end => MarkerState::Valid { start, end },
        (None, None) => MarkerState::NotFound,
        (start, end) => MarkerState::Invalid { start, end },
    }
}

/// Copies `path` to a timestamped `<name>.bak.<timestamp>` sibling and returns
/// the backup path.
///
/// # Errors
///
/// Returns an error when the path has no parent or file name, or the copy
/// fails.
pub(super) fn backup_file(path: &Path) -> Result<PathBuf> {
    let timestamp = chrono::Local::now().format("%Y-%m-%d_%H-%M-%S");

    let parent = path
        .parent()
        .context("config path has no parent directory")?;
    let filename = path.file_name().context("config path has no filename")?;
    let filename_str = filename
        .to_str()
        .context("config filename is not valid UTF-8")?;

    let backup = parent.join(format!("{}.bak.{}", filename_str, timestamp));
    fs::copy(path, &backup).context(format!("Failed to create backup at {}", backup.display()))?;
    Ok(backup)
}

/// Creates a temporary script file for Windows execution.
fn create_temp_script(shell: Shell, script_content: &str) -> Result<(tempfile::TempDir, PathBuf)> {
    use std::io::Write;

    let temp_dir = tempfile::tempdir().context("Failed to create temp directory")?;
    let script_path = temp_dir
        .path()
        .join(format!("forge_script.{}", shell.name()));
    let mut file = fs::File::create(&script_path).context("Failed to create temp script file")?;
    file.write_all(script_content.as_bytes())
        .context("Failed to write temp script")?;

    Ok((temp_dir, script_path))
}

/// Executes a shell script with streaming output.
///
/// # Arguments
///
/// * `shell` - The shell that interprets the script
/// * `script_content` - The script content to execute
/// * `script_name` - Descriptive name for the script (used in error messages)
///
/// # Errors
///
/// Returns error if the script cannot be executed, if output streaming fails,
/// or if the script exits with a non-zero status code
pub(super) fn run_script(shell: Shell, script_content: &str, script_name: &str) -> Result<()> {
    let script_content = super::normalize_script(script_content);
    let shell_name = shell.name();

    // On Unix, pass the script via `<shell> -c`. Command::arg() uses execve,
    // which forwards arguments directly without shell interpretation, so
    // embedded quotes are safe.
    //
    // On Windows, we write the script to a temp file and run `zsh -f <file>`
    // instead. A temp file is necessary because:
    //   1. CI has core.autocrlf=true, so checked-out files contain CRLF; writing
    //      through normalize_script ensures the temp file has LF.
    //   2. CreateProcess mangles quotes, so passing the script via -c corrupts any
    //      embedded quoting.
    //   3. Piping via stdin is unreliable -- Windows caps pipe buffer size, which
    //      can truncate or block on larger scripts.
    // The -f flag also prevents ~/.zshrc from loading during execution.
    // Fish has no native Windows build, so only zsh takes this path.
    let (_temp_dir, mut child) = if cfg!(windows) {
        if shell != Shell::Zsh {
            anyhow::bail!("{shell_name} integration is not supported on Windows");
        }
        let (temp_dir, script_path) = create_temp_script(shell, &script_content)?;
        let child = std::process::Command::new(shell_name)
            // -f: don't load ~/.zshrc (prevents theme loading during doctor)
            .arg("-f")
            .arg(script_path.to_string_lossy().as_ref())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context(format!(
                "Failed to execute {shell_name} {script_name} script"
            ))?;
        // Keep temp_dir alive by boxing it in the tuple
        (Some(temp_dir), child)
    } else {
        let child = std::process::Command::new(shell_name)
            .arg("-c")
            .arg(&script_content)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context(format!(
                "Failed to execute {shell_name} {script_name} script"
            ))?;
        (None, child)
    };

    // Get stdout and stderr handles
    let stdout = child.stdout.take().context("Failed to capture stdout")?;
    let stderr = child.stderr.take().context("Failed to capture stderr")?;

    // Use scoped threads for safer streaming with automatic joining
    std::thread::scope(|s| {
        // Stream stdout line by line
        s.spawn(|| {
            let stdout_reader = BufReader::new(stdout);
            for line in stdout_reader.lines() {
                match line {
                    Ok(line) => println!("{}", line),
                    Err(e) => eprintln!("Error reading stdout: {}", e),
                }
            }
        });

        // Stream stderr line by line
        s.spawn(|| {
            let stderr_reader = BufReader::new(stderr);
            for line in stderr_reader.lines() {
                match line {
                    Ok(line) => eprintln!("{}", line),
                    Err(e) => eprintln!("Error reading stderr: {}", e),
                }
            }
        });
    });

    // Wait for the child process to complete
    let status = child.wait().context(format!(
        "Failed to wait for {shell_name} {script_name} script"
    ))?;

    if !status.success() {
        let exit_code = status
            .code()
            .map_or_else(|| "unknown".to_string(), |code| code.to_string());

        anyhow::bail!(
            "{} {} script failed with exit code: {}",
            shell_name.to_uppercase(),
            script_name,
            exit_code
        );
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use pretty_assertions::assert_eq;

    use super::*;

    #[test]
    fn test_parse_markers_valid() {
        let fixture: Vec<String> = ["a", "# >>> x >>>", "b", "# <<< x <<<", "c"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let actual = matches!(
            parse_markers(&fixture, "# >>> x >>>", "# <<< x <<<"),
            MarkerState::Valid { start: 1, end: 3 }
        );
        let expected = true;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_parse_markers_not_found() {
        let fixture: Vec<String> = vec!["a".to_string()];
        let actual = matches!(
            parse_markers(&fixture, "# >>> x >>>", "# <<< x <<<"),
            MarkerState::NotFound
        );
        let expected = true;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_parse_markers_reversed_is_invalid() {
        let fixture: Vec<String> = ["# <<< x <<<", "# >>> x >>>"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let actual = matches!(
            parse_markers(&fixture, "# >>> x >>>", "# <<< x <<<"),
            MarkerState::Invalid { start: Some(1), end: Some(0) }
        );
        let expected = true;
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_backup_file_creates_timestamped_copy() {
        let temp_dir = tempfile::TempDir::new().unwrap();
        let fixture = temp_dir.path().join("config.fish");
        fs::write(&fixture, "hello").unwrap();

        let backup = backup_file(&fixture).unwrap();

        let actual = (
            backup
                .file_name()
                .unwrap()
                .to_str()
                .unwrap()
                .starts_with("config.fish.bak."),
            fs::read_to_string(&backup).unwrap(),
        );
        let expected = (true, "hello".to_string());
        assert_eq!(actual, expected);
    }
}
