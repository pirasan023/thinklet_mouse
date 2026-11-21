# Development workflow

- Commit each completed change after reviewing the diff and running checks appropriate to the change. Do not leave completed work uncommitted.
- Keep commits focused and describe the resulting behavior in the commit message.
- Before committing or publishing, check staged files for secrets, personal information, device identifiers, local paths, captures and diagnostic logs.
- Never commit `.local-signing/`, private keys, passwords, keychains, build artifacts or local environment files. Keep local signing material intact on the developer's machine.
- Do not push or publish future changes unless the user requests it; committing locally is the default.
- If the environment blocks writing `.git`, local Git metadata may be stored in ignored `work/git/`. When it exists, use `git --git-dir=work/git --work-tree=.` for Git commands and preserve that history.
