## Host Notes

- `razy` should remain on NVIDIA PRIME offload in non-docked mode to preserve battery life.
- Do not propose or switch `razy` to sync mode as a fallback for suspend/resume issues unless explicitly requested.

## Tmux Notes

- Do not use `tmux display-message` for notifications or helper feedback.
- Attention in tmux should be surfaced through status-bar window number color changes, such as bell/activity styling.
