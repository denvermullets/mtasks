---
description: Review recent commits and prepend a new user-facing changelog entry to CHANGELOG.md
---

You are updating `CHANGELOG.md` at the repo root with a new entry summarizing recent shipped work for end users of the mtasks app.

## Steps

1. **Read the SHA marker.** Read the first line of `CHANGELOG.md`. It should match `<!-- last-sha: <hash> -->`.
   - If the file or marker exists, capture the hash and verify it's reachable: `git cat-file -e <hash>`. If it's not (e.g. a rebase rewrote history and orphaned the SHA), **stop** and ask me how to proceed — don't silently re-summarize everything.
   - **First run** (file or marker missing): treat this as a full-history pass — no limit. The repo is small (a few months old); cover everything.

2. **Find new commits.**
   - Normal run: `git log <hash>..HEAD --no-merges --oneline`.
   - First run: `git log --no-merges --oneline --reverse` (entire history, oldest-first).
   - If the output is empty, print `no new commits since last changelog entry` and **stop**. Do not modify the file.

3. **Group commits into user-visible themes.**
   - Read the commit messages (and `git show <sha> --stat` if a message is opaque) to understand each change.
   - Drop pure-internal commits: dependency bumps, tooling/CI/test-only, refactors with no user-visible effect, comment/docs-only changes.
   - Fold related commits into a single bullet (e.g., several filter fixes → one "Better filtering" bullet).
   - **On a first run with lots of history**, produce multiple dated sections grouped by week or by themed batches rather than one giant list. Keep each section under ~6 bullets. Use the commit dates (`git log --format='%ci %h %s'`) to inform grouping.

4. **Write 2–5 plain-speak bullets.** Tone:
   - Speak to the user, not to engineers. "Issue comments now support @mentions" — not "Refactored CommentsController to add user mention parsing."
   - No commit hashes, no PR numbers, no internal ticket IDs (e.g. JAIT-124) in the bullet text. Those live in git history, not in front of users.
   - Optional: lead each bullet with a short bold lead-in (`**Comments on issues.**`) followed by the plain-language description, matching the style of existing entries.

5. **Prepend a new section.** Insert directly under the SHA-marker line and the `# What's new` heading (or after the last existing `## YYYY-MM-DD` section's preceding marker — match the file's current shape). Format:
   ```
   ## YYYY-MM-DD
   - **<lead-in>** <plain-language description>
   - …
   ```
   Use today's date (`date +%Y-%m-%d`). Do not modify any prior dated entries.

6. **Update the SHA marker.** Replace the value in `<!-- last-sha: ... -->` on line 1 with `git rev-parse HEAD`.

7. **Show the diff and stop.** Run `git diff CHANGELOG.md` so I can review. Do not commit. Do not push.

## Hard rules

- Only edit `CHANGELOG.md`. Don't touch other files.
- Never invent changes that aren't in the commit log.
- Skip commits that only modify `CHANGELOG.md` itself — those are the doc-update commits from prior runs of this command and should never be summarized.
- If unsure whether something is user-visible, leave it out — better to under-claim than to mention a non-shipping change.
