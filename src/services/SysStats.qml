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
    // Intel only: the RC6 residency counter (GPU idle milliseconds) and the
    // clock in MHz. i915 has no utilisation counter, so load is the complement
    // of the idle fraction between two polls, differenced here because the
    // polling process has no memory between invocations.
    property real gpuRc6Ms: -1
    property real gpuRc6Stamp: 0
    property real gpuActMhz: 0
    property real gpuMaxMhz: 0
    property real ramTotal: 0
    property real ramUsed: 0
    property int fan1: 0
    property int fan2: 0
    // yogafan hwmon reads 0 RPM even when the fans spin (EC auto-control), so
    // activity is derived from heat and sustained load only. Platform profile is
    // deliberately not a term: `balanced` is the default and would pin this true
    // at a 35 °C idle, and a profile name is not evidence the EC spun anything.
    readonly property bool fanActive: fan1 > 0 || fan2 > 0
                                      || cpuTemp >= 50
                                      || cpuUsage >= 25
    property real diskTotal: 0
    property real diskUsed: 0
    property real diskUsedPct: 0
    // CPU label from config.json; GPU name is auto-detected from nvidia-smi
    // (real model), falling back to config for AMD.
    readonly property string cpuName: ShellConfig.cpuName
    property string gpuName: ShellConfig.gpuName

    // The GPU card's subtitle. On Intel the clock is the only live number next
    // to the residency-derived load, so it goes where the model name would.
    readonly property string gpuDetail: {
        if (root.gpuName !== "Intel" || root.gpuMaxMhz <= 0)
            return root.gpuName
        return "Intel · " + Math.round(root.gpuActMhz) + "/"
               + Math.round(root.gpuMaxMhz) + " MHz"
    }

    // Always on: the bar reads fanActive/cpuTemp live, so telemetry can't
    // freeze while only the monitor popup is closed.
    property var pollTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    function poll() {
        // Bar consumers (fanActive/cpuTemp/cpuUsage) need live values;
        // GPU/mem/disk feed only the monitor popup, so poll those only while
        // it is open. The popup's own on-open Connections fires poll() too.
        tempProc.running = false; tempProc.running = true
        cpuProc.running = false; cpuProc.running = true
        fanProc.running = false; fanProc.running = true
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

    // Usage is the average over the whole poll interval, not a snapshot: one
    // /proc/stat read per poll, differenced against the previous read, so a 5 s
    // refresh reports 5 s of load rather than whatever the last fraction of a
    // second looked like. iowait counts as busy, as in the previous formula.
    property real cpuTotal: 0
    property real cpuIdleTotal: 0
    property var cpuProc: Process {
        command: ["bash", "-c",
            "read -r _ u n s i w q sq st rest < /proc/stat; " +
            "echo $((u+n+s+i+w+q+sq+st)) $i"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (cpuProc.stdout.text || "").trim().split(" ")
                var total = parseFloat(p[0])
                var idle = parseFloat(p[1])
                if (isNaN(total) || isNaN(idle))
                    return
                var dTotal = total - root.cpuTotal
                if (root.cpuTotal > 0 && dTotal > 0)
                    root.cpuUsage = Math.max(0, Math.min(100,
                        (dTotal - (idle - root.cpuIdleTotal)) * 100 / dTotal))
                root.cpuTotal = total
                root.cpuIdleTotal = idle
            }
        }
    }

    // Intel, last: the i915 GPU reaches userspace through three files and no
    // sensor of its own. Frequency comes from the driver's own gt_act/gt_max
    // pair (rps_act/rps_max under the newer gt/gt0 layout); the empty window
    // reports -1 for temperature, which the reader fills from the CPU package
    // sensor because the iGPU is on that same die.
    function applyIntel(p) {
        var t = parseFloat(p[0])
        root.gpuTemp = t < 0 ? root.cpuTemp : (t || 0)
        root.gpuActMhz = parseFloat(p[1]) || 0
        root.gpuMaxMhz = parseFloat(p[2]) || 0
        root.gpuPower = 0
        root.gpuName = "Intel"

        var rc6 = parseFloat(p[3])
        var now = Date.now()
        var wall = now - root.gpuRc6Stamp
        // A gap longer than a minute is a closed panel or a sleep, not a
        // measurement: the residency counter stops while the machine is
        // suspended but the wall clock does not, which would read as 100 %.
        if (!isNaN(rc6) && root.gpuRc6Ms >= 0 && root.gpuRc6Stamp > 0
                && wall > 0 && wall < 60000)
            root.gpuUsage = Math.max(0, Math.min(100,
                100 * (1 - (rc6 - root.gpuRc6Ms) / wall)))
        root.gpuRc6Ms = isNaN(rc6) ? -1 : rc6
        root.gpuRc6Stamp = now
    }

    property var gpuProc: Process {
        // nvidia-smi when present; amdgpu falls back to its hwmon edge sensor
        // and outputs degrees by dividing the millidegree raw value in bash;
        // Intel emits its own five-field line.
        command: ["bash", "-c",
            "if command -v nvidia-smi >/dev/null 2>&1; then " +
            "nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,name --format=csv,noheader,nounits; " +
            "elif [ -r /sys/class/drm/card0/gt_act_freq_mhz ] || [ -r /sys/class/drm/card0/gt/gt0/rps_act_freq_mhz ]; then " +
            "d=/sys/class/drm/card0; n=gt; " +
            "[ -r \"$d/gt_act_freq_mhz\" ] || { d=$d/gt/gt0; n=rps; }; " +
            "read -r a < \"$d/${n}_act_freq_mhz\"; read -r m < \"$d/${n}_max_freq_mhz\"; " +
            "r=0; if [ -r /sys/class/drm/card0/power/rc6_residency_ms ]; then " +
            "read -r r < /sys/class/drm/card0/power/rc6_residency_ms; fi; " +
            "echo \"-1,${a:-0},${m:-0},${r:-0},Intel\"; " +
            "else " +
            "t=$(for h in /sys/class/hwmon/hwmon*; do " +
            "case \"$(cat \"$h/name\" 2>/dev/null)\" in amdgpu) cat \"$h/temp1_input\" 2>/dev/null; exit;; esac; done); " +
            "echo \"$(( ${t:-0} / 1000 )),0,0\"; fi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var line = (gpuProc.stdout.text || "").trim().split("\n")[0]
                var p = line.split(",")
                if (p.length >= 5 && p[4].trim() === "Intel") {
                    root.applyIntel(p)
                    return
                }
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