# Bilingual README Redesign

## Summary

Redesign the project README around a product-first reading flow and add a
fully synchronized Simplified Chinese edition.

The English README remains the repository default at `README.md`. The new
Chinese edition lives at `README.zh-CN.md`. Both files use the same structure,
technical facts, links, commands, and warnings while allowing natural wording
in each language.

## Goals

- Help a first-time visitor understand the product before encountering
  implementation details.
- Make the demo and the project's four main benefits visible near the top.
- Provide an idiomatic Simplified Chinese README with the same information as
  the English README.
- Improve readability and remove repeated explanations without changing the
  product's documented behavior.
- Keep both language editions straightforward to maintain together.

## Non-goals

- Adding or changing application functionality.
- Claiming support for platforms, features, or distribution methods that the
  project does not currently provide.
- Adding a license, contribution guide, roadmap, or other repository policy.
- Changing release artifacts, download URLs, build commands, test commands, or
  runtime requirements.

## Files and language navigation

- `README.md` remains the English default.
- `README.zh-CN.md` is the Simplified Chinese edition.
- Each file begins with an `English | 简体中文` language switcher.
- The current language is bold plain text; the alternate language is a
  relative link to the other README.
- Both files contain matching heading levels, section order, code blocks,
  links, warnings, and media.

## Product-first opening

The opening area is centered and contains:

1. The product name.
2. A concise one-sentence description.
3. Non-status Shields.io badges for `macOS 14+`, `Swift 6`, `Local-only`, and
   `Read-only`, each with matching alternative text.
4. The existing animated demo, linked to the existing high-quality MP4.
5. A compact summary of the four key benefits:
   - usage and rate-limit overview;
   - 60-day Token history;
   - live interactive session visibility;
   - local-only, read-only operation.

This content precedes installation and implementation details so visitors can
quickly decide whether the project is relevant to them.

## Shared section structure

The English and Chinese files use this order:

1. Product introduction and demo
2. Key features
3. Why the project exists
4. Privacy and read-only design
5. Requirements
6. Quick start
   - Apple Silicon preview download
   - Build from source
7. Data and Token semantics
8. Tests
9. Project notes and disclaimers

The exact heading text may be localized, but the hierarchy and meaning remain
the same.

## Content editing rules

- Preserve all current factual claims, version numbers, download links,
  checksum links, commands, paths, requirements, and safety warnings.
- Moderately polish the English wording for clarity, brevity, and a
  professional open-source tone.
- Translate meaning rather than sentence structure so the Chinese edition
  reads naturally.
- Merge repeated first-launch, ad-hoc signing, and notarization guidance into a
  single clear explanation in the relevant section.
- Present privacy information as explicit behavioral guarantees followed by
  only the implementation details needed to substantiate them.
- Do not introduce claims that cannot be supported by the current repository.

## Terminology

Product and technical terms remain consistent across both editions:

- Keep `Codex`, `Codex Menu Bar`, `Token`, `SwiftUI`, `TUI`, and `JSONL` in
  their established forms.
- Keep commands, file paths, environment variables, artifact names, and code
  unchanged.
- Use Chinese technical-writing conventions for punctuation and spacing in the
  Chinese edition.

## Validation

Before completion:

- Compare the two files to confirm matching heading levels and section order.
- Compare code blocks, links, warnings, and media references for parity.
- Confirm all repository-relative media links resolve to existing files.
- Confirm the release download and checksum links are identical across both
  editions.
- Check Markdown headings, tables, badges, and warning blocks for valid GitHub
  rendering.
- Run the project's existing test command and report the result.

## Delivery

All work stays on the `docs/readme-bilingual-redesign` branch. The design
document is committed before implementation planning. Subsequent README changes
will be committed on the same branch and delivered through a Pull Request to
`main`.
