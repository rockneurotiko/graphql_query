# How to release

Because we use
[`RustlerPrecompiled`](https://hexdocs.pm/rustler_precompiled/RustlerPrecompiled.html),
releasing is a bit more involved than it would be otherwise.

1. Pick the new release `version`.

    * We follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
    * Should be the current version in `VERSION` with `-dev` removed if no major changes happened.

1. Begin drafting a new release.

    1. Go to https://github.com/rockneurotiko/graphql_query/releases.
    1. Click "Draft a new release".
    1. Under "Select tag", set the tag to `v{version}`, e.g. `v0.3.0`.
    1. Keep the target branch as `main`.
    1. Click "Generate release notes".
    1. Stop here. Wait until later to actually publish the release.

1. Open a PR with any changes needed for the release. Must include:

    * Updating the `version` in `VERSION`
    * Updating the `version` in any other files that reference it, like
        * `README.md`
        * Do a `grep` or `rg` with the version number to check the files

1. Merge the PR.

1. On the release draft page, click "Publish release".

1. Publishing the release will kick off the "Build precompiled NIFs" GitHub
   Action. Wait for this to complete.

    * It usually takes around 5-10 minutes.

1. Generate the artifact checksums.

    1. Go to your local version of `graphql_query`.
    1. Ensure you have the latest version of `main` (post PR merge).
    1. Execute `bin/fetch_checksums.sh` to generate the checksums

1. Paste the checksums into the release description on GitHub.

    1. Go to the release published earlier at the top of
       https://github.com/rockneurotiko/graphql_query/releases.
    1. Click the "Edit" pencil icon.
    1. At the bottom, paste the SHA256 contents under the heading "SHA256 of the
       artifacts" (ensure the contents are formatted to look like code).

1. Run `mix hex.publish`.

    1. Double check the dependencies and files.
    1. Enter "Y" to confirm.
    1. Discard the auto-generated `.exs` file beginning with `checksum`.

1. Bump the version in the `VERSION` file and add the `-dev` flag to the end.

    * Example: `0.3.0` to `0.3.1-dev`.
    * Can either open up a PR or push directly to `main`.
