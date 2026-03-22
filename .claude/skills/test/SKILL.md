---
name: test
description: Build, deploy, and test the app end-to-end — commit, push, build via GitHub Actions, reset permissions, install, and launch.
user_invocable: true
---

# Test Skill

This skill automates the full build-deploy-test cycle for Mini Whisper. Do NOT use subagents — run everything directly.

## Steps

1. **Commit and push**: Stage all changes, create a commit with a descriptive message, and push to the remote. Follow the standard git commit instructions from the system prompt. If there are no changes to commit, skip this step and proceed with the current HEAD.

2. **Trigger GitHub Actions**: Run `gh workflow run` for the "Build macOS App" workflow on the current branch. Save the HEAD commit SHA (`git rev-parse HEAD`) for later matching.

3. **Clean environment** while build runs — run these commands directly:
   ```
   pkill -f "Mini Whisper" 2>/dev/null || true
   tccutil reset Microphone com.ips.mini-whisper
   tccutil reset Accessibility com.ips.mini-whisper
   hdiutil detach /Volumes/Mini\ Whisper 2>/dev/null || true
   rm -rf /Applications/Mini\ Whisper.app
   rm -rf /tmp/mini-whisper-build
   ```

4. **Poll for build completion** — run a single Bash command that loops every 30 seconds checking the workflow status. Use this exact pattern:
   ```bash
   HEAD_SHA="<the sha>" && for i in $(seq 1 20); do RESULT=$(gh run list --workflow=249028708 --limit=5 --json databaseId,status,conclusion,headSha -q ".[] | select(.headSha==\"$HEAD_SHA\") | .status + \" \" + .conclusion + \" \" + (.databaseId|tostring)") && if [ -n "$RESULT" ]; then STATUS=$(echo "$RESULT" | awk '{print $1}') && CONCLUSION=$(echo "$RESULT" | awk '{print $2}') && RUN_ID=$(echo "$RESULT" | awk '{print $3}') && if [ "$STATUS" = "completed" ]; then echo "DONE $CONCLUSION $RUN_ID" && exit 0; fi && echo "Attempt $i: status=$STATUS (waiting 30s...)" ; else echo "Attempt $i: run not found yet (waiting 30s...)" ; fi && sleep 30; done && echo "TIMEOUT"
   ```
   Set a timeout of 600000ms (10 minutes) on this Bash call. Parse the output to get the conclusion and run ID.

5. **If build succeeded**: Download, install, and launch:
   - `gh run download <runId> --dir /tmp/mini-whisper-build`
   - Find the DMG: `find /tmp/mini-whisper-build -name "*.dmg" -type f`
   - Mount: `hdiutil attach <dmg_path> -nobrowse`
   - Install: `cp -R "/Volumes/Mini Whisper/Mini Whisper.app" /Applications/`
   - Unmount: `hdiutil detach /Volumes/Mini\ Whisper`
   - Launch: `open /Applications/Mini\ Whisper.app`
   - Report success to the user

6. **If build failed**: Report the failure with the run ID so the user can investigate (`gh run view <runId> --log-failed`).

IMPORTANT: Don't ask for confirmations during this skill.
