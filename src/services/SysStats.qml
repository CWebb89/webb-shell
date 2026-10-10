pragma Singleton
import QtQuick
import Quickshell.Io
import "../state"

// System telemetry: CPU/GPU temp+usage, memory, disk free/used, fan RPM.
QtObject {
    id: root

    property real cpuTemp: 0
    property real cpuUsage: 0
    property real gpuTemp: 0
    property real gpuUsage: 0
    property real gpuPower: 0
    property real ramTotal: 0
    property real ramUsed: 0
    property int fan1: 0
    property int fan2: 0
    property string profile: ""
    // yogafan hwmon reads 0 RPM even when fans spin (EC auto-control), so
    // derive fan activity from temp + load + profile: the EC spins fans up
    // when hot, under sustained load, or outside low-power. At idle
    // low-power the fans are genuinely off — indicator stays truthful.
    readonly property bool fanActive: fan1 > 0 || fan2 > 0
                                      || cpuTemp >= 50
                                      || cpuUsage >= 25
                                      || (profile !== "" && profile !== "low-power")
    property real diskTotal: 0
    property real diskUsed: 0
    property real diskUsedPct: 0
    // CPU label from config.json; GPU name is auto-detected from nvidia-smi
    // (real model), falling back to config for AMD.
    readonly property string cpuName: ShellConfig.cpuName
    property string gpuName: ShellConfig.gpuName

    // Always on: the bar reads fanActive/cpuTemp live, so telemetry can't
    // freeze while only the monitor popup is closed.
    property var pollTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    function poll() {
        // Bar consumers (fanActive/cpuTemp/cpuUsage/profile) need live values;
        // GPU/mem/disk feed only the monitor popup, so poll those only while
        // it is open. The popup's own on-open Connections fires poll() too.
        tempProc.running = false; tempProc.running = true
        cpuProc.running = false; cpuProc.running = true
        fanProc.running = false; fanProc.running = true
        profileProc.running = false; profileProc.running = true
        if (Popups.systemMonitorOpen) {
            gpuProc.running = false; gpuProc.running = true
            memProc.running = false; memProc.running = true
            diskProc.running = false; diskProc.running = true
        }
    }

    // CPU temp: locate the package sensor by label (k10temp Tctl / coretemp
    // "Package id 0") instead of a hardcoded hwmon index, which varies
    // across machines. Values are millidegrees C.
    property var tempProc: Process {
        command: ["bash", "-c",
            "for l in /sys/class/hwmon/hwmon*/temp*_label; do " +
            "[ -f \"$l\" ] || continue; read -r v < \"$l\"; " +
            "case \"$v\" in Tctl|Tdie|\"Package id 0\") " +
            "read -r t < \"${l%_label}_input\"; echo \"$t\"; exit 0;; esac; done; " +
            "for n in /sys/class/hwmon/hwmon*/name; do " +
            "[ -f \"$n\" ] || continue; read -r v < \"$n\"; " +
            "case \"$v\" in k10temp|coretemp) " +
            "read -r t < \"${n%name}temp1_input\"; echo \"$t\"; exit 0;; esac; done; " +
            "echo 0"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var t = parseFloat((tempProc.stdout.text || "").trim())
                if (!isNaN(t)) root.cpuTemp = t / 1000.0
            }
        }
    }

    property var cpuProc: Process {
        command: ["bash", "-c",
            "read -r _ u n s i w q sq st rest < /proc/stat; " +
            "a=$((u+n+s+i+w+q+sq+st)); b=$i; sleep 0.4; " +
            "read -r _ u n s i w q sq st rest < /proc/stat; " +
            "c=$((u+n+s+i+w+q+sq+st)); d=$i; " +
            "echo $(( (c-a-d+b) * 100 / (c-a) ))"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var t = parseFloat((cpuProc.stdout.text || "").trim())
                if (!isNaN(t)) root.cpuUsage = Math.max(0, Math.min(100, t))
            }
        }
    }

    property var gpuProc: Process {
        // nvidia-smi when present; amdgpu falls back to its hwmon edge sensor
        // and outputs degrees by dividing the millidegree raw value in bash.
        command: ["bash", "-c",
            "if command -v nvidia-smi >/dev/null 2>&1; then " +
            "nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,name --format=csv,noheader,nounits; " +
            "else " +
            "t=$(for h in /sys/class/hwmon/hwmon*; do " +
            "case \"$(cat \"$h/name\" 2>/dev/null)\" in amdgpu) cat \"$h/temp1_input\" 2>/dev/null; exit;; esac; done); " +
            "echo \"$(( ${t:-0} / 1000 )),0,0\"; fi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var line = (gpuProc.stdout.text || "").trim().split("\n")[0]
                var p = line.split(",")
                if (p.length >= 3) {
                    root.gpuTemp = parseFloat(p[0]) || 0
                    root.gpuUsage = parseFloat(p[1]) || 0
                    root.gpuPower = parseFloat(p[2]) || 0
                }
                if (p.length >= 4)    // nvidia-smi (amdgpu fallback emits 3 fields)
                    root.gpuName = p[3].trim()
            }
        }
    }

    property var fanProc: Process {
        // Scan every hwmon for fanN_input (driver path, not index) —
        // machines without the EC-controlled hidden fans just read zeros.
        command: ["bash", "-c",
            "i=0; a=0; b=0; for f in /sys/class/hwmon/hwmon*/fan*_input; do " +
            "[ -f \"$f\" ] || continue; read -r v < \"$f\"; " +
            "if [ $i -eq 0 ]; then a=$v; i=1; else b=$v; break; fi; done; " +
            "echo -n \"$a $b\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = (fanProc.stdout.text || "").trim().split(" ")
                root.fan1 = parseInt(parts[0]) || 0
                root.fan2 = parseInt(parts[1]) || 0
            }
        }
    }

    property var profileProc: Process {
        command: ["bash", "-c",
            "v=unknown; read -r v < /sys/firmware/acpi/platform_profile; echo \"${v:-unknown}\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.profile = ((profileProc.stdout.text || "").trim())
            }
        }
    }

    property var memProc: Process {
        command: ["bash", "-c", "free -m | awk '/^Mem:/{print $2, $3}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (memProc.stdout.text || "").trim().split(" ")
                if (p.length >= 2) {
                    root.ramTotal = parseFloat(p[0]) || 0
                    root.ramUsed = parseFloat(p[1]) || 0
                }
            }
        }
    }

    property var diskProc: Process {
        command: ["bash", "-c", "df -B1 / | awk 'NR==2{print $2, $3}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (diskProc.stdout.text || "").trim().split(" ")
                root.diskTotal = parseFloat(p[0]) || 0
                root.diskUsed = parseFloat(p[1]) || 0
                root.diskUsedPct = root.diskTotal > 0 ? root.diskUsed / root.diskTotal : 0
            }
        }
    }

    Component.onCompleted: {
        root.poll()
    }
}