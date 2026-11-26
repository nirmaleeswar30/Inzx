# Linux miniplayer

The mini button switches to artwork and lyrics controls and requests a 320 × 340
window. Expand restores the previous normal window. Transitions are queued so
repeated presses cannot leave the player permanently busy.

## Window handling

- Hyprland: identify INZX by process ID and window address, then use targeted
  compositor commands to float and resize it. Hyprland 0.57+ supports targeted
  fullscreen exit. On older versions, leave fullscreen before pressing mini.
  If capture fails (missing hyprctl, timeout, or no matching window), use the
  standard GTK backend instead.
- Other Linux desktops: use the existing GTK backend (window_manager on nativeapi). Inspect
  native fullscreen/maximized state, wait for those states to clear, then retry
  and verify the requested size. Preserve maximization and keep-above on expand.
  Keep-above is optional; an unsupported operation does not prevent mini mode.
- A compositor can refuse application resize requests, particularly for tiled
  windows. Retries are bounded. Failed entry restores the normal view and attempts
  to restore its window state; the user can float the window and retry. There is
  no universal Wayland command to force a window to float. Window position and
  keep-above remain compositor-dependent.

## Verification

After rebasing onto upstream `7bc1f22`, three fullscreen → 320 × 340 mini →
restore cycles passed on Hyprland 0.57.2 using a temporary native GTK window.
Automated tests cover capture failures and the fullscreen lyrics guard, plus native
fullscreen exit, delayed size changes, refused resizing, unsupported keep-above,
state restoration, repeated transitions, and the targeted Hyprland commands.
The generic backend has not yet been manually verified on GNOME, KDE, Xfce,
Sway or other desktops. This is broader Linux support, not an all-compositor
compatibility guarantee. Windows and macOS retain their existing fallback path.
