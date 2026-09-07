use gh_workflow::generate::Generate;
use gh_workflow::*;

use crate::jobs::{self, ReleaseBuilderJob};
use crate::steps::setup_protoc;

/// Generate the main CI workflow
pub fn generate_ci_workflow() {
    // Create a basic build job for CI with coverage
    let build_job = Job::new("Build and Test")
        .permissions(Permissions::default().contents(Level::Read))
        .add_step(Step::new("Checkout Code").uses("actions", "checkout", "v6"))
        .add_step(setup_protoc())
        .add_step(Step::toolchain().add_stable())
        .add_step(Step::new("Install cargo-llvm-cov").run("cargo install cargo-llvm-cov"))
        .add_step(
            Step::new("Generate coverage")
                .run("cargo llvm-cov --all-features --workspace --lcov --output-path lcov.info"),
        );

    // Create a performance test job to ensure zsh rprompt stays fast
    let perf_test_job = Job::new("zsh-rprompt-performance")
        .name("Performance: zsh rprompt")
        .permissions(Permissions::default().contents(Level::Read))
        .add_step(Step::new("Checkout Code").uses("actions", "checkout", "v6"))
        .add_step(setup_protoc())
        .add_step(Step::toolchain().add_stable())
        .add_step(
            Step::new("Run performance benchmark")
                .run("./scripts/benchmark.sh --threshold 60 zsh rprompt"),
        );

    // Same budget for the fish right prompt, which runs on every prompt too
    let fish_perf_test_job = Job::new("fish-rprompt-performance")
        .name("Performance: fish rprompt")
        .permissions(Permissions::default().contents(Level::Read))
        .add_step(Step::new("Checkout Code").uses("actions", "checkout", "v6"))
        .add_step(setup_protoc())
        .add_step(Step::toolchain().add_stable())
        .add_step(
            Step::new("Run performance benchmark")
                .run("./scripts/benchmark.sh --threshold 60 fish rprompt"),
        );

    // Parse the generated fish plugin/theme with a real fish and drive the
    // Enter/Tab bindings under a pty against a fake forge binary
    let fish_plugin_job = Job::new("fish-plugin")
        .name("Fish plugin")
        .permissions(Permissions::default().contents(Level::Read))
        .add_step(Step::new("Checkout Code").uses("actions", "checkout", "v6"))
        .add_step(setup_protoc())
        .add_step(Step::toolchain().add_stable())
        .add_step(
            Step::new("Install fish 4").run(
                "sudo apt-add-repository -y ppa:fish-shell/release-4 && sudo apt-get update && sudo apt-get install -y fish && fish --version",
            ),
        )
        .add_step(Step::new("Build forge").run("cargo build -p forge_main"))
        .add_step(Step::new("Test fish plugin").run("./scripts/test-fish-plugin.sh"));

    let draft_release_job = jobs::create_draft_release_job("build");
    let draft_release_pr_job = jobs::create_draft_release_pr_job();
    let events = Event::default()
        .push(Push::default().add_branch("main").add_tag("v*"))
        .pull_request(
            PullRequest::default()
                .add_type(PullRequestType::Opened)
                .add_type(PullRequestType::Synchronize)
                .add_type(PullRequestType::Reopened)
                .add_type(PullRequestType::Labeled)
                .add_branch("main"),
        );
    let build_release_pr_job =
        ReleaseBuilderJob::new("${{ needs.draft_release_pr.outputs.crate_release_name }}")
            .into_job()
            .add_needs("draft_release_pr")
            .cond(Expression::new(
                [
                    "github.event_name == 'pull_request'",
                    "contains(github.event.pull_request.labels.*.name, 'ci: build all targets')",
                ]
                .join(" && "),
            ));
    let build_release_job =
        ReleaseBuilderJob::new("${{ needs.draft_release.outputs.crate_release_name }}")
            .release_id("${{ needs.draft_release.outputs.crate_release_id }}")
            .into_job()
            .add_needs("draft_release")
            .cond(Expression::new(
                [
                    "github.event_name == 'push'",
                    "github.ref == 'refs/heads/main'",
                ]
                .join(" && "),
            ));
    let workflow = Workflow::default()
        .name("ci")
        .add_env(RustFlags::deny("warnings"))
        .on(events)
        .concurrency(Concurrency::default().group("${{ github.workflow }}-${{ github.ref }}"))
        .add_env(("OPENROUTER_API_KEY", "${{secrets.OPENROUTER_API_KEY}}"))
        .add_job("build", build_job)
        .add_job("zsh_rprompt_perf", perf_test_job)
        .add_job("fish_rprompt_perf", fish_perf_test_job)
        .add_job("fish_plugin", fish_plugin_job)
        .add_job("draft_release", draft_release_job)
        .add_job("draft_release_pr", draft_release_pr_job)
        .add_job("build_release", build_release_job)
        .add_job("build_release_pr", build_release_pr_job);

    Generate::new(workflow).name("ci.yml").generate().unwrap();
}
