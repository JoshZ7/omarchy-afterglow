import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
  id: root

  property var bar
  property string moduleName
  property var settings
  property int revision: 0
  property int bandCount: 28
  property var levels: Array(bandCount).fill(0)
  property bool hasSignal: false
  // Themes may supply a Cava-specific ramp; otherwise use their standard palette.
  property var themeColors: ({})
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + (moduleName || "io.github.joshz7.afterglow")
  property string statePath: Quickshell.env("HOME") + "/.cache/cava-now-playing/bars"
  // "bonfire" deliberately ignores the active desktop theme.
  readonly property string colorMode: settings && settings.colorMode ? String(settings.colorMode) : "theme"
  // A theme may set cava_hover to a colour, or "none" to turn hover feedback
  // off just for that theme. The widget-wide hoverFeedback setting defaults on.
  readonly property bool hoverFeedbackEnabled: (!settings || settings.hoverFeedback !== false)
    && (colorMode === "bonfire" || themeColors.cava_hover !== "none")
  readonly property color interactionColor: colorMode === "bonfire"
    ? "#FF6A22"
    : ((themeColors.cava_hover && themeColors.cava_hover !== "none")
      ? themeColors.cava_hover
      : (themeColors.cava_3 || themeColors.cyan || themeColors.green || (bar ? bar.foreground : "white")))
  readonly property var mediaPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasTrack: activePlayer && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string trackLabel: activePlayer
    ? ((activePlayer.trackTitle || "Unknown track") + (activePlayer.trackArtist ? "  ·  " + activePlayer.trackArtist : ""))
    : ""
  // Plugin settings: showNextButton / hoverFeedback (default true), doubleClickSkips (default false).
  readonly property bool showNextButton: !settings || settings.showNextButton !== false
  readonly property bool doubleClickSkips: settings && settings.doubleClickSkips === true
  readonly property int collapsedWidth: settings && Number(settings.collapsedWidth) > 0 ? Number(settings.collapsedWidth) : 178
  readonly property int expandedWidth: settings && Number(settings.expandedWidth) > 0 ? Number(settings.expandedWidth) : 348
  readonly property string sparkIntensity: settings && settings.sparkIntensity ? String(settings.sparkIntensity) : "subtle"
  readonly property real sparkRiseThreshold: sparkIntensity === "lively" ? 0.06 : 0.09
  readonly property real sparkLevelThreshold: sparkIntensity === "lively" ? 0.13 : 0.17
  property int mediaClickSequence: 0
  property bool expanded: mediaHover.hovered && hasTrack

  // A player can replace its metadata while the panel remains open. Start the
  // new title at the beginning instead of inheriting the prior title's offset.
  onTrackLabelChanged: {
    trackText.x = 0
    if (expanded && trackText.width > trackViewport.width) trackMarquee.restart()
  }

  // Track hover across the whole widget, including child controls and padding.
  HoverHandler {
    id: mediaHover
  }

  function selectActivePlayer() {
    var fallback = null
    for (var i = 0; i < mediaPlayers.length; i++) {
      var player = mediaPlayers[i]
      if (!player || !(player.trackTitle || player.trackArtist)) continue
      if (player.isPlaying) return player
      if (!fallback) fallback = player
    }
    return fallback
  }

  function raiseActivePlayer() {
    if (activePlayer && activePlayer.dbusName) {
      Quickshell.execDetached([
        "busctl", "--user", "call", activePlayer.dbusName,
        "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "Raise"
      ])
    } else if (bar) {
      bar.run("omarchy-launch-or-focus-tui cava")
    }
  }

  function toggleActivePlayer() {
    if (!activePlayer) return
    if (activePlayer.isPlaying && activePlayer.canPause) activePlayer.pause()
    else if (!activePlayer.isPlaying && activePlayer.canPlay) activePlayer.play()
    else if (activePlayer.canTogglePlaying) activePlayer.togglePlaying()
  }

  function skipNext() {
    if (activePlayer && activePlayer.canGoNext) activePlayer.next()
  }

  function previousTrack() {
    if (activePlayer && activePlayer.canGoPrevious) activePlayer.previous()
  }

  // Wait briefly to distinguish one, two, and three clicks. Double-clicks
  // use MouseArea's native event rather than hand-rolled press counting.
  Timer {
    id: mediaGestureTimer
    // Let the third press arrive at a normal human triple-click pace; the
    // ordinary single-click path remains snappy.
    interval: root.mediaClickSequence === 2 ? 520 : 260
    onTriggered: {
      const count = root.mediaClickSequence
      root.mediaClickSequence = 0
      if (count === 1) root.toggleActivePlayer()
      else if (count === 2) root.skipNext()
      else if (count >= 3) root.previousTrack()
    }
  }

  function loadThemeColors(raw) {
    const next = ({})
    const lines = String(raw || "").split("\n")
    for (let i = 0; i < lines.length; i++) {
      const match = lines[i].match(/^\s*(cyan|green|yellow|orange|red|bright_red|cava_[1-5]|cava_hover)\s*=\s*[\"']?(#[0-9A-Fa-f]{6}|none)/)
      if (match) next[match[1]] = match[2]
    }
    themeColors = next
  }

  function colorForLevel(level) {
    const palette = colorMode === "bonfire" ? [
      "#7E3B25", "#E34528", "#FF6A22", "#FFC15A", "#FFDA7D"
    ] : [
      themeColors.cava_1 || themeColors.cyan || (bar ? bar.foreground : "#9FC9D0"),
      themeColors.cava_2 || themeColors.green || (bar ? bar.foreground : "#C1C479"),
      themeColors.cava_3 || themeColors.yellow || (bar ? bar.foreground : "#FFDA7D"),
      themeColors.cava_4 || themeColors.orange || (bar ? bar.urgent : "#FF6A22"),
      themeColors.cava_5 || themeColors.bright_red || themeColors.red || (bar ? bar.urgent : "#FF6042")
    ]
    return palette[Math.min(palette.length - 1, Math.floor(Math.max(0, level) * palette.length))]
  }

  implicitWidth: !(hasSignal || hasTrack) ? 0 : (bar && bar.vertical ? bar.barSize : (expanded ? expandedWidth : collapsedWidth))
  implicitHeight: bar ? bar.barSize : 30
  visible: hasSignal || hasTrack

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  function loadFrame(frame) {
    const values = String(frame || "").trim().split(";")
    const next = []
    for (let i = 0; i < bandCount; i++) {
      const start = Math.floor(i * values.length / bandCount)
      const end = Math.floor((i + 1) * values.length / bandCount)
      let peak = 0
      for (let j = start; j < end; j++) peak = Math.max(peak, Number(values[j]) || 0)
      next.push(Math.max(0, Math.min(15, peak)) / 15)
    }
    levels = next
    // Keep very quiet tracks visible, while a true all-zero CAVA frame hides it.
    hasSignal = Math.max.apply(null, next) > 0
    revision += 1
  }

  function startCava() {
    Quickshell.execDetached([pluginDir + "/cava-pulse", pluginDir + "/cava.conf", statePath])
  }

  Component.onCompleted: startCava()
  onModuleNameChanged: if (moduleName) startCava()

  // The helper verifies that bars is an owned, regular file and caps it at
  // 4 KiB before emitting it. FileView would read a FIFO or oversized file
  // before QML could reject it, so the helper is the only frame reader.
  Process {
    id: cavaFrameReader
    command: [root.pluginDir + "/cava-pulse", "--read", root.statePath]
    stdout: SplitParser {
      onRead: function(frame) { root.loadFrame(frame) }
    }
  }

  FileView {
    id: themePalette
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onFileChanged: reload()
  }

  Timer {
    interval: 150
    running: true
    repeat: true
    onTriggered: if (!cavaFrameReader.running) cavaFrameReader.running = true
  }

  // Omarchy can swap the active theme directory without emitting a file-change
  // event for colors.toml, so refresh the palette periodically as well.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: themePalette.reload()
  }

  Item {
    id: mediaPanel
    anchors.left: parent.left
    anchors.right: spectrum.left
    anchors.leftMargin: 4
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height
    clip: true
    opacity: root.expanded ? 1 : 0
    visible: root.hasTrack

    Behavior on opacity {
      NumberAnimation { duration: 120 }
    }

    Text {
      id: playPause
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
      color: root.hoverFeedbackEnabled && mediaControlsHover.containsMouse ? root.interactionColor : (root.bar ? root.bar.foreground : "white")
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 16
    }

    Item {
      id: trackViewport
      anchors.left: playPause.right
      anchors.leftMargin: 8
      anchors.right: nextTrack.left
      anchors.rightMargin: 7
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true

      Text {
        id: trackText
        anchors.verticalCenter: parent.verticalCenter
        text: root.trackLabel
        textFormat: Text.PlainText
        color: root.hoverFeedbackEnabled && mediaControlsHover.containsMouse ? root.interactionColor : (root.bar ? root.bar.foreground : "white")
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: 13
      }

      SequentialAnimation {
        id: trackMarquee
        running: root.expanded && trackText.width > trackViewport.width
        loops: Animation.Infinite
        onRunningChanged: if (!running) trackText.x = 0
        PauseAnimation { duration: 900 }
        NumberAnimation {
          target: trackText
          property: "x"
          from: 0
          to: -(trackText.width - trackViewport.width)
          duration: Math.max(1800, (trackText.width - trackViewport.width) * 28)
          easing.type: Easing.Linear
        }
        PauseAnimation { duration: 1400 }
        NumberAnimation {
          target: trackText
          property: "x"
          to: 0
          duration: 380
          easing.type: Easing.OutCubic
        }
      }
    }

    Text {
      id: nextTrack
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "󰒭"
      visible: root.showNextButton && root.activePlayer && root.activePlayer.canGoNext
      width: visible ? implicitWidth : 0
      color: root.hoverFeedbackEnabled && nextTrackHover.containsMouse ? root.interactionColor : (root.bar ? root.bar.foreground : "white")
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 16
    }

    MouseArea {
      id: mediaControlsHover
      anchors.left: parent.left
      anchors.right: nextTrack.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      enabled: root.hasTrack
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPressed: {
        // A follow-up press may become a double/triple click, so don't let
        // the pending single-click action fire underneath it.
        if (root.doubleClickSkips && root.mediaClickSequence > 0) mediaGestureTimer.stop()
      }
      onClicked: {
        if (!root.doubleClickSkips) {
          root.toggleActivePlayer()
          return
        }
        // First click begins a sequence. After a native double-click, this
        // same handler receives the potential third click.
        if (root.mediaClickSequence === 0 || root.mediaClickSequence === 2) {
          root.mediaClickSequence += 1
          mediaGestureTimer.restart()
        }
      }
      onDoubleClicked: {
        if (!root.doubleClickSkips) return
        mediaGestureTimer.stop()
        root.mediaClickSequence = 2
        mediaGestureTimer.restart()
      }
    }

    MouseArea {
      id: nextTrackHover
      anchors.fill: nextTrack
      enabled: root.activePlayer && root.activePlayer.canGoNext
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.skipNext()
    }
  }

  Row {
    id: spectrum
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    visible: !bar || !bar.vertical

    Repeater {
      model: root.bandCount
      delegate: Item {
        required property int index
        readonly property int _revision: root.revision
        readonly property real level: root.levels[index] || 0
        property real previousLevel: 0
        property int sparkBurst: 0
        width: 3
        height: Math.max(4, root.height - 10)

        onLevelChanged: {
          // Emit only on a real upward hit, avoiding a constant glitter at
          // quiet levels. The particles then fall back into the bar.
          if (root.sparkIntensity !== "off" && level > previousLevel + root.sparkRiseThreshold && level > root.sparkLevelThreshold) sparkBurst += 1
          previousLevel = level
        }

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(2, parent.height * level)
          radius: 1.5
          color: root.colorForLevel(level)
          Behavior on height { NumberAnimation { duration: 45 } }
        }

        Repeater {
          model: 2
          delegate: Rectangle {
            id: spark
            required property int index
            width: 2
            height: 2
            radius: 1
            x: index === 0 ? 0 : parent.width - width
            property real landingY: Math.max(0, parent.height * (1 - level) - 2)
            y: landingY
            opacity: 0
            color: root.colorForLevel(level)

            onLandingYChanged: {
              if (!falling.running) y = landingY
            }

            Connections {
              target: parent
              function onSparkBurstChanged() { falling.restart() }
            }

            ParallelAnimation {
              id: falling
              NumberAnimation {
                target: spark
                property: "y"
                from: Math.max(0, spark.landingY - 10 - spark.index * 3)
                to: spark.landingY + 1
                duration: 620 + spark.index * 120
                easing.type: Easing.InQuad
              }
              NumberAnimation {
                target: spark
                property: "opacity"
                from: 0.9
                to: 0
                duration: 760 + spark.index * 120
              }
            }
          }
        }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: bar && bar.vertical
    text: "▂▅█"
    color: bar ? bar.foreground : "white"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: 10
  }

  MouseArea {
    anchors.fill: spectrum
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (bar) bar.showTooltip(root, "CAVA · PipeWire spectrum")
    onExited: if (bar) bar.hideTooltip(root)
    onClicked: root.raiseActivePlayer()
  }
}
