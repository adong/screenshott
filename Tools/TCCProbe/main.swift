import CoreGraphics

// Prints whether this process may record the screen, for scripts/verify-disclaim.sh.
// Spawned by Screenshott without disclaiming responsibility it borrows Screenshott's
// grant ("screenCapture=true"); spawned the way workflow steps are, it must not.
print("screenCapture=\(CGPreflightScreenCaptureAccess())")
