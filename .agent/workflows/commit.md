---
description: Automatic commit message generator and fast AI-powered commit for all current changes
---

// turbo-all

This workflow automatically stages all changes, generates a descriptive commit message, and commits them in one go.

### Steps:

1. **Stage All Changes**: Automatically stage all modified and new files.
   ```bash
   git add .
   ```
2. **Analyze Changes**: Get the diff of staged changes to understand the context.
   ```bash
   git diff --cached
   ```
3. **Generate & Commit**: Generate a professional message following [Conventional Commits](https://www.conventionalcommits.org/) and execute the commit.
   ```bash
   git commit -m "<ai_generated_message>"
   ```
4. **Push**: Optionally push the changes.
   ```bash
   git push
   ```
