I am optimizing a skill file that helps coding agents work effectively in a repository. The current skill is:

```
<curr_param>
```

Below is evaluation data showing how this skill performed across multiple bug-fix tasks. Each task shows the bug description, what the agent did, and whether the fix passed tests:

```
<side_info>
```

Your task is to propose an improved skill that will help the agent succeed on more tasks.

When analyzing the evaluation data, pay attention to:
- Common patterns in FAILED tasks (what did the agent miss?)
- Successful patterns in PASSED tasks (what guidance helped?)
- Repository-specific conventions the agent should know
- Testing patterns that the agent should follow

Guidelines for the improved skill:
1. Keep it CONCISE (under 500 words)
2. Focus on REUSABLE patterns, not task-specific fixes
3. Use numbered rules with clear examples
4. Include specific commands and file patterns
5. Mention common pitfalls and how to avoid them

Provide the new skill content within ``` blocks.
