# eCRF toolkit integration

The maintained source is `ecrf_pipeline/` in the Trial Biostatistics Toolkit. The four browser entry points are under [docs/app](docs/index.html); they accept users’ CSV data through guided forms without installing Python or downloading this repository.

The complete history of `patrickiben/ecrf-pipeline-apps` was imported with a Git subtree from commit `d39327253b16240effab4325360ff402c9982bcd`. Its [Apache-2.0 license](LICENSE), [NOTICE](NOTICE), original synthetic data, evaluation outputs and registered evaluation plan remain with this module. The toolkit’s top-level MIT license does not replace the eCRF license.

## Browser and native paths

- Browser workspaces start blank. Examples load only when selected. Uploads, settings and results remain in the current tab’s memory; the user downloads result packages explicitly.
- Coding uses supplied terminology and lexical candidates, with no automatic coding approval. The example dictionary uses placeholder codes.
- De-identification uses pattern and literal-term review. Cleaned field exports and sensitive review material are separate downloads.
- Participant screening uses declared rule weights and configurable criteria. Its indices are not probabilities. Fatal-outcome mapping is distinct from life-threatening severity.
- Monitoring uses robust z scores, a 200-point quantile approximation to one-dimensional Wasserstein distance, and bag-of-words text isolation. Visit pairing, units, minimum group sizes and missingness rules are explicit.
- The original optional native trained-model/SAS-file paths remain available in the local programs. They are not represented as browser capabilities. Server-hosted demo mode still disables uploads; a browser flag is accepted only on the WebAssembly platform.

The original evaluation describes the earlier synthetic/native workflow. New browser input, export and scientific boundary checks are recorded separately in [QC_REPORT.md](QC_REPORT.md).
