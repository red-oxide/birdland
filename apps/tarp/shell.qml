// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import Niri
import modules.theme
import modules.util

// Tarp: the lock screen. It runs in the background and locks every monitor
// with `birdland-tarp ipc call tarp lock`; the user's password, checked by
// PAM, unlocks it, and so does a touch of a security key (or a fingerprint)
// when keyPamService is set. There is deliberately no IPC call that unlocks.
//
// If tarp dies while locked, the compositor keeps the screens locked. A
// state file in $XDG_RUNTIME_DIR records that, so the next tarp (systemd
// restarts it) locks again at once and the password can unlock the session.
//
// Settings come from TARP_CONFIG, a JSON file (the Home Manager module writes
// one), or else from single environment variables:
//
//   JSON key       variable              meaning
//   pamService     TARP_PAM_SERVICE      PAM service in /etc/pam.d (default "login")
//   keyPamService  TARP_KEY_PAM_SERVICE  PAM service that asks for nothing typed,
//                                        such as pam_u2f alone; run the whole time
//                                        the screen is locked (default: none)
//   wallpaper      TARP_WALLPAPER        image or folder behind the lock ("~/" = home)
//   fill           -                     wallpaper fill: fill, fit, stretch, center, tile
ShellRoot {
    id: root

    JsonSettings {
        id: settings

        variable: "TARP_CONFIG"
    }

    readonly property var config: settings.values

    readonly property string pamService: config.pamService ?? Env.get("TARP_PAM_SERVICE", "login")
    readonly property string keyPamService: config.keyPamService ?? Env.get("TARP_KEY_PAM_SERVICE", "")
    readonly property string wallpaper: Env.expandHome(String(config.wallpaper ?? Env.get("TARP_WALLPAPER")))
    readonly property string fill: String(config.fill ?? "fill")
    readonly property string userName: Env.get("USER")

    // Authentication state, shown on every monitor.
    property string prompt: "Password"
    property bool promptEchoes: false
    property string message: ""
    property bool messageIsError: false
    // From the key check, such as "Please touch the device."; shown while
    // there is no message.
    property string hint: ""
    // Set when the key check can't work (the service is missing or asks for
    // something typed); it is tried again at the next lock.
    property bool keyCheckBroken: false
    readonly property bool busy: pam.active && !pam.responseRequired
    // Typed before PAM asked for it; handed over at PAM's first question.
    property var pendingResponse: null

    signal failed

    function lock() {
        if (sessionLock.locked)
            return;
        reset();
        message = "";
        hint = "";
        keyCheckBroken = false;
        stateFile.setText("locked\n");
        sessionLock.locked = true;
        startKeyCheck();
    }

    function startKeyCheck() {
        if (keyPamService === "" || keyCheckBroken || !sessionLock.locked || keyPam.active)
            return;
        keyPam.startedAt = Date.now();
        if (!keyPam.start()) {
            keyCheckBroken = true;
            console.warn("tarp: could not start the key check (PAM service \"" + keyPamService + "\")");
        }
    }

    function submit(text) {
        message = "";
        if (pam.active && pam.responseRequired) {
            pam.respond(text);
            return;
        }
        if (pam.active)
            return;
        pendingResponse = text;
        if (!pam.start()) {
            pendingResponse = null;
            showError("Could not start authentication (PAM service \"" + pamService + "\")");
        }
    }

    function reset() {
        pendingResponse = null;
        prompt = "Password";
        promptEchoes = false;
    }

    function showError(text) {
        reset();
        message = text;
        messageIsError = true;
        failed();
    }

    function unlock() {
        keyRetry.stop();
        if (keyPam.active)
            keyPam.abort();
        if (pam.active)
            pam.abort();
        reset();
        message = "";
        hint = "";
        sessionLock.locked = false;
        stateFile.setText("unlocked\n");
    }

    PamContext {
        id: pam

        config: root.pamService

        onPamMessage: {
            if (responseRequired) {
                if (root.pendingResponse !== null) {
                    const response = root.pendingResponse;
                    root.pendingResponse = null;
                    respond(response);
                } else {
                    // A further question, such as a one-time code.
                    root.prompt = message.replace(/:\s*$/, "");
                    root.promptEchoes = responseVisible;
                }
            } else if (message !== "") {
                root.message = message;
                root.messageIsError = messageIsError;
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success)
                root.unlock();
            else if (result !== PamResult.Error) // onError has said why
                root.showError(result === PamResult.MaxTries ? "Too many attempts" : "Incorrect password");
        }

        onError: error => root.showError("Authentication error: " + PamError.toString(error))
    }

    // The key check: beside the password check, for the whole time the screen
    // is locked, so a touch unlocks without typing anything. An attempt ends
    // when the device stops waiting for a touch (or at once with no device
    // plugged in), and the next starts shortly after.
    PamContext {
        id: keyPam

        property double startedAt: 0

        config: root.keyPamService

        onPamMessage: {
            if (responseRequired) {
                // A PIN or password: typing goes to the password check.
                console.warn("tarp: PAM service \"" + root.keyPamService + "\" asked for input (\"" + message + "\"); the key check needs one that asks for nothing typed");
                root.keyCheckBroken = true;
                abort();
            } else if (message !== "") {
                root.hint = message;
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlock();
                return;
            }
            // Over at once: no device plugged in, so drop a stale hint.
            if (Date.now() - startedAt < 2000)
                root.hint = "";
            keyRetry.restart();
        }
    }

    Timer {
        id: keyRetry

        interval: 2000
        onTriggered: root.startKeyCheck()
    }

    // "locked" while locked; see the comment at the top.
    FileView {
        id: stateFile

        path: Env.get("XDG_RUNTIME_DIR") === "" ? "" : Env.get("XDG_RUNTIME_DIR") + "/birdland-tarp.state"
        blockLoading: true
        blockWrites: true
        printErrors: false
    }

    Component.onCompleted: {
        if (stateFile.path !== "" && stateFile.text().trim() === "locked") {
            console.warn("tarp: the previous lock screen exited while locked; locking again");
            lock();
        }
    }

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface

            color: Theme.background

            LockView {
                anchors.fill: parent
                lock: root
            }
        }
    }

    // For screenOff below.
    Niri {
        id: niri

        Component.onCompleted: connect()
    }

    IpcHandler {
        target: "tarp"

        // Turn the monitors off (they come back on with any input); the
        // Home Manager module runs this when idle. Works locked or not.
        function screenOff(): bool {
            const result = niri.sendRawAction({
                PowerOffMonitors: {}
            });
            if (!result.ok)
                console.warn("tarp: could not turn the monitors off:", result.error);
            return result.ok;
        }

        // Lock every monitor. Returns at once; see isSecure.
        function lock(): void {
            root.lock();
        }

        function isLocked(): bool {
            return sessionLock.locked;
        }

        // True once the compositor confirms every monitor is covered.
        function isSecure(): bool {
            return sessionLock.secure;
        }
    }
}
