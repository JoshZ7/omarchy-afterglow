import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

Item {
  id: root

  property var bar
  property string moduleName
  property var settings
  property int revision: 0
  readonly property int configuredBandCount: settings && Number(settings.spectrumBars) > 0
    ? Math.max(20, Math.min(48, Number(settings.spectrumBars))) : 28
  property int previewBandCount: configuredBandCount
  property bool resizingSpectrum: false
  property int bandCount: previewBandCount
  property var levels: Array(bandCount).fill(0)
  property bool hasSignal: false
  // Themes may supply a Cava-specific ramp; otherwise use their standard palette.
  property var themeColors: ({})
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + (moduleName || "io.github.joshz7.afterglow")
  property string statePath: Quickshell.env("HOME") + "/.cache/cava-now-playing/bars"
  readonly property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
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
  readonly property string trackTitle: boundedText(activePlayer ? activePlayer.trackTitle : "", 160)
  readonly property string trackArtist: boundedText(activePlayer ? activePlayer.trackArtist : "", 120)
  readonly property bool hasTrack: activePlayer && (trackTitle || trackArtist)
  readonly property string trackLabel: boundedText(trackTitle
    ? (trackTitle + (trackArtist ? "  ·  " + trackArtist : ""))
    : trackArtist, 280)
  // Plugin settings: showNextButton / hoverFeedback (default true), doubleClickSkips (default false).
  readonly property bool showPlayPauseButton: !settings || settings.showPlayPauseButton !== false
  readonly property bool showNextButton: settings && settings.showNextButton === true
  readonly property bool doubleClickSkips: settings && settings.doubleClickSkips === true
  readonly property int collapsedWidth: settings && Number(settings.collapsedWidth) > 0 ? Number(settings.collapsedWidth) : 178
  readonly property int expandedWidth: settings && Number(settings.expandedWidth) > 0 ? Number(settings.expandedWidth) : 348
  readonly property string emberMode: !settings || !settings.sparkIntensity ? "normal"
    : (settings.sparkIntensity === "subtle" ? "normal"
      : (settings.sparkIntensity === "lively" ? "full" : String(settings.sparkIntensity)))
  readonly property int emberCount: emberMode === "full" ? 22 : (emberMode === "soft" ? 7 : (emberMode === "off" ? 0 : 14))
  onConfiguredBandCountChanged: if (!resizingSpectrum) previewBandCount = configuredBandCount
  property int mediaClickSequence: 0
  property bool expanded: mediaHover.hovered && hasTrack
  property bool settingsOpen: false
  property double lastFrameAt: 0

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

  function boundedText(value, limit) {
    const text = String(value || "")
    return text.length > limit ? text.slice(0, Math.max(0, limit - 1)) + "…" : text
  }

  function updateSetting(key, value) {
    settings = Object.assign({}, settings || {}, { [key]: value })
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
  }

  function close() {
    settingsOpen = false
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

  implicitWidth: !(hasSignal || hasTrack) ? 0 : (bar && bar.vertical ? bar.barSize : (expanded ? Math.max(expandedWidth, bandCount * 6 + 177) : Math.max(collapsedWidth, bandCount * 6 + 9)))
  implicitHeight: bar ? bar.barSize : 30
  visible: hasSignal || hasTrack

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  function loadFrame(frame) {
    const rawValues = String(frame || "").trim().split(";")
    const values = []
    for (let i = 0; i < rawValues.length; i++) {
      const raw = rawValues[i].trim()
      const value = Number(raw)
      if (raw !== "" && isFinite(value)) values.push(value)
    }
    if (values.length === 0) return
    const next = []
    // Every display width summarizes the complete Cava frame: narrow views
    // combine adjacent frequencies; wide views split them back out.
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
    lastFrameAt = Date.now()
    revision += 1
  }

  function startCava() {
    if (cavaProcess.running) return
    cavaStopping = false
    cavaProcess.running = true
  }

  function stopCava() {
    if (!cavaProcess.running) return
    cavaStopping = true
    cavaProcess.signal(15)
    cavaStopTimer.restart()
  }

  Component.onCompleted: startCava()
  onModuleNameChanged: if (moduleName) startCava()
  Component.onDestruction: stopCava()

  property bool cavaStopping: false

  Process {
    id: cavaProcess
    command: [root.pluginDir + "/cava-pulse", root.pluginDir + "/cava.conf", root.statePath]
    onExited: cavaStopTimer.stop()
  }

  Timer {
    id: cavaStopTimer
    interval: 1200
    repeat: false
    onTriggered: if (cavaProcess.running) cavaProcess.signal(9)
  }

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

  Process {
    id: themePaletteReader
    command: [root.pluginDir + "/cava-pulse", "--read-theme", root.themePath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadThemeColors(text)
    }
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: if (!cavaFrameReader.running) cavaFrameReader.running = true
  }

  // PipeWire/Cava may stop publishing frames entirely when playback pauses.
  // Do not leave the final live spectrum frozen on screen in that case.
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (root.hasSignal && root.lastFrameAt > 0 && Date.now() - root.lastFrameAt > 250) {
        root.levels = Array(root.bandCount).fill(0)
        root.hasSignal = false
        root.revision += 1
      }
    }
  }

  // Omarchy can swap the active theme directory without emitting a file-change
  // event for colors.toml, so refresh the palette periodically as well.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: if (!themePaletteReader.running) themePaletteReader.running = true
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
      visible: root.showPlayPauseButton
      width: visible ? contentWidth : 0
      color: root.hoverFeedbackEnabled && mediaControlsHover.containsMouse ? root.interactionColor : (root.bar ? root.bar.foreground : "white")
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 16
    }

    Item {
      id: trackViewport
      anchors.left: playPause.right
      anchors.leftMargin: playPause.visible ? 8 : 0
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
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: function(mouse) {
        // A follow-up press may become a double/triple click, so don't let
        // the pending single-click action fire underneath it.
        if (mouse.button === Qt.LeftButton && root.doubleClickSkips && root.mediaClickSequence > 0) mediaGestureTimer.stop()
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          root.settingsOpen = !root.settingsOpen
          return
        }
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
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.settingsOpen = !root.settingsOpen
        else root.skipNext()
      }
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
        width: 3
        height: Math.max(4, root.height - 10)

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(2, parent.height * level)
          radius: 1.5
          color: root.colorForLevel(level)
          Behavior on height { NumberAnimation { duration: 45 } }
        }
      }
    }
  }

  // A few independent embers make the spectrum feel like a small fire rather
  // than a beat-by-beat particle fountain. They always float upward.
  Item {
    id: emberLayer
    anchors.right: spectrum.right
    anchors.verticalCenter: spectrum.verticalCenter
    width: spectrum.width
    height: spectrum.height
    z: 2
    visible: spectrum.visible && root.hasSignal && root.emberMode !== "off"

    Repeater {
      model: root.emberCount
      delegate: Rectangle {
        id: ember
        required property int index
        width: index % 3 === 0 ? 3 : 2
        height: width
        radius: width / 2
        opacity: 0
        property real startY: 0
        property real endY: 0
        property color emberColor: "white"
        color: emberColor

        function launch() {
          const activeBands = []
          for (let band = 0; band < root.bandCount; band++) {
            if ((root.levels[band] || 0) > 0.04) activeBands.push(band)
          }
          // Wait for a live bar instead of letting an ember originate from
          // empty space. Its already-running flight is left untouched.
          if (activeBands.length === 0) {
            nextEmber.interval = 120 + Math.floor(Math.random() * 380)
            nextEmber.restart()
            return
          }
          const band = activeBands[Math.floor(Math.random() * activeBands.length)]
          const level = root.levels[band] || 0
          const bandWidth = parent.width / root.bandCount
          x = Math.max(0, Math.min(parent.width - width, (band + 0.5) * bandWidth - width / 2))
          startY = Math.max(0, parent.height * (1 - level) - 2)
          endY = -5 - Math.random() * 13
          y = startY
          // Stay in the warm middle of the ramp: no pale/white embers.
          emberColor = root.colorForLevel(0.2 + Math.random() * 0.35)
          rise.duration = 1050 + Math.floor(Math.random() * 1250)
          fade.duration = rise.duration
          riseAndFade.restart()
        }

        Component.onCompleted: nextEmber.restart()

        Timer {
          id: nextEmber
          interval: 80 + Math.floor(Math.random() * 550)
          repeat: false
          onTriggered: ember.launch()
        }

        ParallelAnimation {
          id: riseAndFade
          onStopped: {
            nextEmber.interval = 150 + Math.floor(Math.random() * 650)
            nextEmber.restart()
          }
          NumberAnimation {
            id: rise
            target: ember
            property: "y"
            from: ember.startY
            to: ember.endY
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            id: fade
            target: ember
            property: "opacity"
            from: 0.72
            to: 0
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
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onEntered: if (bar) bar.showTooltip(root, "CAVA · PipeWire spectrum")
    onExited: if (bar) bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.settingsOpen = !root.settingsOpen
      else root.raiseActivePlayer()
    }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.settingsOpen
    contentWidth: fittedContentWidth(236)
    contentHeight: fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: 8

      Text {
        text: "Ember settings"
        color: Color.foreground
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: 14
      }

      Text {
        text: "Colour"
        color: Color.foreground
        opacity: 0.82
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: 11
      }

      Row {
        width: parent.width
        spacing: 6
        Repeater {
          model: [
            { label: "Match theme", value: "theme" },
            { label: "Ember", value: "bonfire" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: (settingsColumn.width - 6) / 2
            height: 27
            radius: 5
            color: root.colorMode === modelData.value ? root.interactionColor : Color.background
            border.width: 1
            border.color: root.colorMode === modelData.value ? root.interactionColor : Color.muted
            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: root.colorMode === modelData.value ? Color.background : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : "sans-serif"
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.updateSetting("colorMode", modelData.value)
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Color.muted; opacity: 0.45 }

      Item {
        width: parent.width
        height: 27
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Skip button"
          color: Color.foreground
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: 12
        }
        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 38
          height: 20
          radius: 10
          color: root.showNextButton ? root.interactionColor : Color.muted
          Rectangle {
            width: 16
            height: 16
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: root.showNextButton ? parent.width - width - 2 : 2
            color: Color.background
            Behavior on x { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.updateSetting("showNextButton", !root.showNextButton)
          }
        }
      }

      Item {
        width: parent.width
        height: 27
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Play/pause button"
          color: Color.foreground
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: 12
        }
        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 38
          height: 20
          radius: 10
          color: root.showPlayPauseButton ? root.interactionColor : Color.muted
          Rectangle {
            width: 16
            height: 16
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: root.showPlayPauseButton ? parent.width - width - 2 : 2
            color: Color.background
            Behavior on x { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.updateSetting("showPlayPauseButton", !root.showPlayPauseButton)
          }
        }
      }

      Text {
        text: "Embers"
        color: Color.foreground
        opacity: 0.82
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: 11
      }

      Row {
        width: parent.width
        spacing: 4
        Repeater {
          model: [
            { label: "Off", value: "off" },
            { label: "Soft", value: "soft" },
            { label: "Normal", value: "normal" },
            { label: "Full", value: "full" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: (settingsColumn.width - 12) / 4
            height: 27
            radius: 5
            color: root.emberMode === modelData.value ? root.interactionColor : Color.background
            border.width: 1
            border.color: root.emberMode === modelData.value ? root.interactionColor : Color.muted
            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: root.emberMode === modelData.value ? Color.background : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : "sans-serif"
              font.pixelSize: 10
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.updateSetting("sparkIntensity", modelData.value)
            }
          }
        }
      }

      Item {
        width: parent.width
        height: 42
        Text {
          text: "Visualiser width  ·  " + root.previewBandCount + " bars"
          color: Color.foreground
          opacity: 0.82
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: 11
        }
        Rectangle {
          id: widthTrack
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 4
          radius: 2
          color: Color.muted
          opacity: 0.55
          Rectangle {
            width: parent.width * (root.previewBandCount - 20) / 28
            height: parent.height
            radius: parent.radius
            color: root.interactionColor
          }
          Rectangle {
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * (root.previewBandCount - 20) / 28 - width / 2
            color: root.interactionColor
          }
          Rectangle {
            // Magnetic home mark: the original 28-bar visualiser width.
            width: 2
            height: 10
            radius: 1
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * (28 - 20) / 28 - width / 2
            color: Color.foreground
            opacity: 0.8
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeHorCursor
            function previewAt(position) {
              let bands = Math.round(20 + Math.max(0, Math.min(width, position)) / width * 28)
              if (Math.abs(bands - 28) <= 1) bands = 28
              root.previewBandCount = bands
            }
            onPressed: function(mouse) {
              root.resizingSpectrum = true
              previewAt(mouse.x)
            }
            onPositionChanged: function(mouse) {
              if (pressed) previewAt(mouse.x)
            }
            onReleased: {
              root.resizingSpectrum = false
              root.updateSetting("spectrumBars", root.previewBandCount)
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Color.muted; opacity: 0.45 }

      Text {
        width: parent.width
        text: "Click: play/pause\nDouble-click: next\nTriple-click: previous\nClick visualiser: focus audio player"
        color: Color.foreground
        opacity: 0.82
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: 10
        wrapMode: Text.WordWrap
      }
    }
  }
}
