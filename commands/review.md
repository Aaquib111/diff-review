---
description: Apply my review comments to the current diff
allowed-tools: Bash(cat:*)
---
Here are my review comments on your current diff, as JSON:

!`cat .claude/review.json`

For each comment: open the file at `path`, locate the target using `start_line`–`end_line`,
but if the lines no longer match, find the region by matching the `snippet` text (I may have
made manual edits that shifted line numbers). When the two disagree, prefer the `snippet`.
Apply the change described in `body`. When done, summarize what you changed, grouped by comment.
