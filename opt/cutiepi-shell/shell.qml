/*
    Copyright (C) 2021 Penk Chen
    Copyright (C) 2021 Chouaib Hamrouche

    Contact: hello@cutiepi.io

    This file is part of CutiePi shell of the CutiePi project.

    CutiePi shell is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    CutiePi shell is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with CutiePi shell. If not, see <https://www.gnu.org/licenses/>.

*/

import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.1
import QtMultimedia 5.15 

import QtWebEngine 1.7
import QtQuick.VirtualKeyboard 2.2
import QtQuick.VirtualKeyboard.Settings 2.2
import QtQuick.LocalStorage 2.0
import QtGraphicalEffects 1.0

import Qt.labs.settings 1.0

import QtSensors 5.11

import MeeGo.Connman 0.2 
import Yat 1.0 as Yat

import McuInfo 1.0
import Process 1.0
import "tabControl.js" as Tab 

Window {  
    id: view
    width: 800
    height: 1280
    visible: true

    Rectangle { anchors.fill: parent; color: '#ececec' }

    property variant formatDateTimeString: "HH:mm"
    property variant batteryPercentage: ""
    property variant queue: []
    property bool screenLocked: false
    property bool switchoffScreen: false

    property bool batteryCharging: false
    property variant wallpaperUrl: settings.value("wallpaperUrl", "file:///usr/share/rpd-wallpaper/boombox.png");
    property variant wallpaperFontColor: 'white' // '#525353'

    property real pitch: 0.0
    property real roll: 0.0
    readonly property double radians_to_degrees: 180 / Math.PI

    property variant orientation: 270
    property variant portraitMode: (orientation === 180 || orientation === 0)
    property variant sensorEnabled: true 
    property variant keyboardPosition: { 
        '270': { x: -40, y: 440, hidden_x: 360, hidden_y: 440 }, 
        '180': { x: 0,  y: 0, hidden_x: 0, hidden_y: -250 }, 
        '90': { x: -440, y: 440, hidden_x: -840, hidden_y: 440 }, 
        '0': { x: 0, y: 1030, hidden_x: 0, hidden_y: 1280 } 
    } 

    property string mcuVersion: ""
    property string currentTab: ""
    property bool hasTabOpen: (tabModel.count !== 0) && (typeof(Tab.itemMap[currentTab]) !== "undefined")

    property alias systemSettings: settings
    Settings {
        id: settings
    }

    Component.onCompleted: {
        mcuInfo.start();
        Tab.openNewAppTab("page-"+Tab.salt(), 'factorymode');
        process.start("rfkill", ["unblock", "all"]);

        setScreenBrightness(100);
        setAudioVolume(80);
    }

    function loadUrlWrapper(url) { Tab.loadUrl(url) }

    function turnScreenOn() { setScreenBrightness(50 + brightnessSlider.value) }
    function turnScreenOff() { setScreenBrightness(0) }
    function setAudioVolume(vol) { process.start("amixer", ["set", "Master", vol+"%"]); }
    function setScreenBrightness(val) { process.start("/opt/cutiepi-shell/assets/setBrightness", [val]); }

    function setSystemClock() {
        systemClock.text = Qt.formatDateTime(new Date(), formatDateTimeString);
        lockscreenTime.text = Qt.formatDateTime(new Date(), "HH:mm");
        lockscreenDate.text = Qt.formatDateTime(new Date(), "dddd, MMMM d"); 
    }

    onScreenLockedChanged: {
        if (screenLocked) {
            turnScreenOff();
            root.state = "locked";
            process.start("sudo", ["cpufreq-set", "-g", "powersave"]);
            orientation = 270; 
            sensorEnabled = false;
        } else {
            turnScreenOn();
            process.start("sudo", ["cpufreq-set", "-g", "conservative"]);
        }
    }

    onSwitchoffScreenChanged: {
        turnScreenOn();
        if (switchoffScreen) {
            root.state = "switchoff";
        } else {
            root.state = "normal"
        }
    }

    Timer {
        id: scanTimer
        interval: (root.state == "setting") ? 5000 : 30000
        running: networkingModel.powered && ( root.state !== "locked" )
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            networkingModel.requestScan()
        }
    }

    TechnologyModel {
        id: networkingModel
        name: "wifi"
        property string networkName
    }

    NetworkManager { 
        id: networkManager
        onConnectedChanged: { if (connected) wifiIndicator.source = "icons/network-wireless-signal-excellent-symbolic.svg" }
    }

    UserAgent {
        id: userAgent
        onUserInputRequested: {
            root.state = "popup"
            scanTimer.running = false;
            passwordInput.text = "";
            console.log('user input requested: ' + networkingModel.networkName)
            var view = { 
                "fields": []
            };
            for (var key in fields) {
                view.fields.push({
                    "name": key,
                    "id": key.toLowerCase(),
                    "type": fields[key]["Type"],
                    "requirement": fields[key]["Requirement"]
                });
                console.log(key + ":");
                for (var inkey in fields[key]) {
                    console.log("    " + inkey + ": " + fields[key][inkey]);
                }
            }
        }
        onErrorReported: {
            console.log('Error: ' + error);
            notification.showNotification('Error: ' + error);
            wifiIndicator.source = "icons/network-wireless-signal-none-symbolic.svg";
        }
    }

    Process { id: process }

    McuInfo {
        id: mcuInfo
        portName: "/dev/ttyS0"
        portBaudRate: 115200

        property variant batteryAttributes: 
            { '4.20': 100, '3.99': 95, '3.97': 90, '3.92': 85, '3.87': 80, '3.83': 75, '3.79': 70, 
              '3.75': 65, '3.73': 60, '3.70': 55, '3.68': 50, '3.66': 45, '3.65': 40, '3.63': 35, 
              '3.62': 30, '3.60': 25, '3.58': 20, '3.545': 15, '3.51': 10, '3.42': 5, '3.00': 0 }

        onButtonChanged: {
            if (button == 1)
                screenLocked = !screenLocked;
            if (button == 3)
                switchoffScreen = true;
        }
        onBatteryChanged: {
            var currentVol = (battery/1000).toFixed(2); 
            var sum = 0; 
            queue.push(currentVol); 
            if (queue.length > 10)
                queue.shift()
            for (var i = 0; i < queue.length; i++) {
                sum += parseFloat(queue[i])
            }
            var meanVol = (sum/queue.length).toFixed(2);
            for (var vol in batteryAttributes) {
                if (meanVol >= parseFloat(vol)) { 
                    var volPercent = batteryAttributes[vol];
                    batteryPercentage = volPercent
                    break;
                }
            }
        }
        onChargeChanged: {
            if (charge == 4) batteryCharging = true 
            if (charge == 5) batteryCharging = false 
        }
        onVersionChanged: {
            console.log("MCU version: " + version)
            mcuVersion = version;
        }
        Timer { 
            interval: 1000; repeat: true; running: (mcuVersion === ""); onTriggered: mcuInfo.getVersion();
        }
    }

    SoundEffect {
        id: dockingSoundEffect
        source: batteryCharging ? "file:///opt/cutiepi-shell/assets/data_sounds_effects_wav_Dock.wav" 
            : "file:///opt/cutiepi-shell/assets/data_sounds_effects_wav_Undock.wav"
        onSourceChanged: { 
            dockingSoundEffect.play();
            turnScreenOn();
            if (root.state == "locked") { 
                screenLocked = false;
                idleTimer.start();
            }
        }
    }

    Accelerometer {
        id: accel
        active: sensorEnabled
        dataRate: 30
        onReadingChanged: {
            var accX = accel.reading.x
            var accY = accel.reading.y
            var accZ = -accel.reading.z

            var pitchAcc = Math.atan2(accY, accZ)*radians_to_degrees;
            var rollAcc = Math.atan2(accX, accZ)*radians_to_degrees;

            pitch = pitch * 0.98 + pitchAcc * 0.02;
            roll = roll * 0.98 + rollAcc * 0.02;
            
            var tmp = orientation;

            //update orientation
            if(pitch >= 30.0)
                tmp = 0
            else if(pitch <= -30.0)
                tmp = 180
            if(roll >= 30.0)
                tmp = 270
            else if(roll <= -30.0)
                tmp = 90 

            orientation = tmp;
        }
    }

    Gyroscope {
        id: gyro
        active: sensorEnabled
        dataRate: 30
        onReadingChanged: {
            //integrate gyro rates to update angles (pitch and roll)
            var dt=0.01 //10ms
            pitch += gyro.reading.x*dt;
            roll -= gyro.reading.y*dt;
        }
    }

    Rectangle {
        id: root
        color: "#ececec"
        width: portraitMode ? 800 : 1280
        height: portraitMode ? 1280 : 800 

        FontLoader {
            id: fontAwesome
            source: "file:///opt/cutiepi-shell/Font Awesome 5 Free-Solid-900.otf" 
        }

        // control the rotation of view 
        x: portraitMode ? 0 : -240
        y: portraitMode ? 0 : 240
        rotation: orientation
        Behavior on rotation {
            RotationAnimator { duration: 150; easing.type: Easing.InOutQuad; direction: RotationAnimator.Shortest }
        }

        Rectangle {
            id: sidebar  
            height: parent.height + 4
            width: Tab.DrawerWidth + 4
            anchors { left: parent.left; margins: -2; leftMargin: -4; top: parent.top }
            color: '#ececec'
            border.width: 2
            border.color: '#c5c5c3'

            ListModel { id: tabModel }
            Component {
                id: tabDelegate
                Row {
                    spacing: 10
                    Rectangle {
                        width: Tab.DrawerWidth + 2
                        height: 50 
                        color: "transparent"
                        Image { 
                            height: 24; width: 24; 
                            source: hasTabOpen ? Tab.itemMap[model.pageid].icon : "icons/favicon.png";
                            anchors { left: parent.left; margins: Tab.DrawerMargin; verticalCenter: parent.verticalCenter} 
                        }
                        Text { 
                            text: (typeof(Tab.itemMap[model.pageid]) !== "undefined" && Tab.itemMap[model.pageid].title !== "") ? 
                            Tab.itemMap[model.pageid].title : "Loading..";
                            color: "#3e3e3e" 
                            font.pointSize: 7
                            anchors { left: parent.left; margins: Tab.DrawerMargin; verticalCenter: parent.verticalCenter
                                leftMargin: Tab.DrawerMargin+30; right: parent.right; rightMargin: 38 } 
                            elide: Text.ElideRight 
                        }
                        MouseArea { 
                            anchors { top: parent.top; left: parent.left; bottom: parent.bottom; right: parent.right; rightMargin: 40 }
                            enabled: (root.state == "drawer") 
                            onClicked: { 
                                tabListView.currentIndex = index;
                                Tab.switchToTab(model.pageid);
                            }
                        }

                        Rectangle {
                            width: 40; height: 40
                            color: "transparent"
                            anchors { right: parent.right; top: parent.top}
                            Text {  // closeTab button
                                visible: tabListView.currentIndex === index
                                anchors { top: parent.top; right: parent.right; margins: Tab.DrawerMargin; topMargin: Tab.DrawerMargin - 2 }
                                text: "\uF057"
                                font.family: fontAwesome.name
                                font.pointSize: 10
                                color: "gray"

                                MouseArea { 
                                    anchors.fill: parent; anchors.margins: -2 
                                    onClicked: Tab.closeTab(model.index, model.pageid)
                                }
                            }
                        }
                    }
                }
            }
            ListView {
                id: tabListView
                anchors.fill: parent

                // new tab button 
                header: Rectangle { 
                    width: Tab.DrawerWidth
                    height: 80
                    color: "transparent"
                    Text { 
                        text: "\uF067"; font.family: fontAwesome.name; color: "#3e3e3e"; font.pointSize: 10
                        anchors { top: parent.top; left: parent.left; margins: 20; leftMargin: 30 }
                    }
                    Text { 
                        text: "<b>New Tab</b>"
                        color: "#3e3e3e"
                        font.pointSize: 10
                        anchors { top: parent.top; left: parent.left; margins: 20; leftMargin: 70; }
                    }
                    MouseArea { 
                        anchors.fill: parent; 
                        enabled: (root.state == "drawer") 
                        onClicked: {
                            Tab.openNewTab("page-"+Tab.salt(), Tab.HomePage); 
                        }
                        onPressAndHold: {
                            Tab.openNewAppTab("page-"+Tab.salt(), 'terminal');
                        }
                    }
                }

                model: tabModel
                delegate: tabDelegate 
                highlight: Rectangle { 
                    width: Tab.DrawerWidth; height: Tab.DrawerHeight + 10 
                    color: "#d4d4d4"
                }
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1.0; duration: 400 }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 400; easing.type: Easing.OutBounce }
                }
                highlightMoveDuration: 2
                highlightFollowsCurrentItem: true 
                footer: Rectangle { 
                    width: Tab.DrawerWidth
                    height: 80
                    color: "transparent"
                    Text { 
                        text: "\uF013"; font.family: fontAwesome.name; color: "#3e3e3e"; font.pointSize: 10
                        anchors { top: parent.top; left: parent.left; margins: 20; leftMargin: 30 }
                    }
                    Text { 
                        text: "<b>Settings</b>"
                        color: '#3e3e3e'
                        font.pointSize: 10
                        anchors { top: parent.top; left: parent.left; margins: 18; leftMargin: 70; }
                    }
                    MouseArea { 
                        anchors.fill: parent; 
                        enabled: (root.state == "drawer") 
                        onClicked: {
                            Tab.goToSetting();
                        }
                    }
                }
                footerPositioning: ListView.OverlayFooter
            }
        }

        Rectangle { 
            id: content 
            width: parent.width 
            height: parent.height 
            anchors { left: parent.left; top: parent.top; }
            color: "#f7f6f4"
            
            SequentialAnimation { 
                id: tabBounce 
                PropertyAnimation { target: content; properties: "anchors.leftMargin"; to: Tab.DrawerWidth; duration: 200; easing.type: Easing.InOutQuad; }
                PropertyAnimation { target: content; properties: "anchors.leftMargin"; to: "0"; duration: 400; easing.type: Easing.InOutQuad; }
            } 
            Component {
                id: tabWebView
                WebView { 
                    onLoadingChanged: { 
                        urlText.text = Tab.itemMap[currentTab].url;
                        if (loadRequest.status == WebEngineView.LoadSucceededStatus) {
                            Tab.updateHistory(Tab.itemMap[currentTab].url, Tab.itemMap[currentTab].title, Tab.itemMap[currentTab].icon)
                        }
                    }
                    onOpenTab: {
                        Tab.loadUrl(url);
                    }
                    onOpenNewTab: {
                        tabBounce.start();
                        Tab.openNewTab("page-"+Tab.salt(), url); 
                    }
                }
            }
            Component {
                id: tabTermView
                Yat.Screen { 
                    id: terminal
                    property variant url: "cutiepi://terminal"
                    property variant canGoBack: false 
                    property variant title: "Terminal" 
                    property variant icon: "icons/terminal-512.png"
                    anchors.fill: parent 
                    anchors.topMargin: 85
                    font.pointSize: 8 
                    z: 0
                }
            } 
            Component {
                id: tabFactoryModeView 
                FactoryMode {
                    id: factoryMode
                    property variant url: "cutiepi://factorymode"
                    property variant canGoBack: false 
                    property variant title: "Factory Testing Mode" 
                    property variant icon: "icons/terminal-512.png"
                    anchors.fill: parent 
                    anchors.topMargin: 85
                    z: 0 
                }
            }
            Component {
                id: tabSettingView 
                SettingView {
                    id: settingView
                    property variant url: "cutiepi://setting"
                    property variant canGoBack: false 
                    property variant title: "Settings" 
                    property variant icon: "icons/terminal-512.png"
                    anchors.fill: parent 
                    anchors.topMargin: 85
                    z: 0 
                }
            }

            // navi bar 
            Rectangle {
                id: naviBar
                color: "#f7f6f4"
                width: parent.width 
                height: 85
                anchors {
                    top: parent.top
                    right: parent.right
                }
                z: 1

                // hamburger button 
                Text {
                    id: hamburgerButton
                    font.pointSize: 14
                    font.family: fontAwesome.name 
                    text: "\uf0c9"
                    color: '#3e3e3e'
                    anchors {
                        left: parent.left; margins: 22; verticalCenter: parent.verticalCenter;
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -20 
                        // open or close the drawer 
                        onClicked: {
                            root.state == "drawer" ? root.state = "normal" : root.state = "drawer"
                            Qt.inputMethod.hide();
                        }
                    }
                }

                // controls and label for app tabs, only visible if it's an app 
                Text { 
                    visible: hasTabOpen && (Tab.itemMap[currentTab].url.toString().match('cutiepi://') )
                    anchors {  left: hamburgerButton.right; leftMargin: 30; verticalCenter: parent.verticalCenter } 
                    text: Tab.itemMap[currentTab].title; color: "#3e3e3e"; font.pointSize: 12
                }

                Item {
                    id: backButton
                    width: 30; height: 30; anchors { left: hamburgerButton.right; margins: 20; top: parent.top; topMargin: 22 }
                    visible: !hasTabOpen || ! (Tab.itemMap[currentTab].url.toString().match('cutiepi://') )
                    Text { 
                        id: backButtonIcon
                        text: "\uF053" 
                        font { family: fontAwesome.name; pointSize: 15 }
                        color: hasTabOpen ? (Tab.itemMap[currentTab].canGoBack ? "#434C5E" : "lightgray") : "lightgray"
                    }

                    MouseArea { 
                        anchors.fill: parent; anchors.margins: -5; 
                        enabled: hasTabOpen && Tab.itemMap[currentTab].canGoBack 
                        onPressed: backButtonIcon.color = "#bf616a"; 
                        onClicked: { Tab.itemMap[currentTab].goBack() }
                        onReleased: backButtonIcon.color = "#434C5E"; 
                    }
                }
            }

            // url bar 
            Rectangle {
                id: urlBar
                width: parent.width - 510
                height: 55
                color: "#e7e7e5"
                visible: !hasTabOpen || ! (Tab.itemMap[currentTab].url.toString().match('cutiepi://') )
                anchors {
                    top: parent.top
                    left: parent.left
                    margins: 20; topMargin: 15; leftMargin: 125
                }
                radius: 26
                z: 1

                TextInput { 
                    id: urlText
                    text: hasTabOpen ? Tab.itemMap[currentTab].url : ""
                    font.pointSize: 9; color: "#2E3440"; selectionColor: "#4875E2"
                    anchors { left: parent.left; top: parent.top; right: stopButton.left; margins: 11; }
                    height: parent.height
                    inputMethodHints: Qt.ImhNoAutoUppercase // url hint 
                    clip: true
                    
                    onAccepted: { 
                        Tab.loadUrl(urlText.text)
                        urlText.text = urlText.text;
                    }
                    onActiveFocusChanged: { 
                        if (urlText.activeFocus) { 
                            if (hasTabOpen) Tab.itemMap[currentTab].stop();
                            urlText.selectAll(); root.state = "normal"; 
                        } else { 
                            parent.border.color = "#2E3440"; parent.border.width = 0; 
                        }
                    }
                    onTextChanged: {
                        if (urlText.activeFocus && urlText.text !== "") {
                            Tab.queryHistory(urlText.text)
                        } else { historyModel.clear() }
                    }
                }
                Text {
                    id: stopButton
                    anchors { right: urlBar.right; rightMargin: 8; verticalCenter: parent.verticalCenter}
                    text: "\uF00D"
                    font { family: fontAwesome.name; pointSize: 12 }
                    color: "gray"
                    visible: ( hasTabOpen && Tab.itemMap[currentTab].loadProgress < 100 && !urlText.focus) ? true : false
                    MouseArea {
                        anchors { fill: parent; margins: -10; }
                        onClicked: { Tab.itemMap[currentTab].stop(); }
                    }
                }
                Text {
                    id: reloadButton
                    anchors { right: urlBar.right; rightMargin: 8; verticalCenter: parent.verticalCenter}
                    text: "\uF01E"
                    font { family: fontAwesome.name; pointSize: 8 }
                    color: "gray"
                    visible: ( hasTabOpen && Tab.itemMap[currentTab].loadProgress == 100 && !urlText.focus ) ? true : false 
                    MouseArea {
                        anchors { fill: parent; margins: -10; }
                        onClicked: { 
                            Tab.itemMap[currentTab].reload(); 
                            Tab.itemMap[currentTab].updateProfile();
                        }
                    }
                }
                Text {
                    id: clearButton
                    anchors { right: urlBar.right; rightMargin: 8; verticalCenter: parent.verticalCenter}
                    text: "\uF057"
                    font { family: fontAwesome.name; pointSize: 12 }
                    color: "gray"
                    visible: urlText.focus
                    MouseArea {
                        anchors { fill: parent; margins: -10; }
                        onClicked: { urlText.text = ""; urlText.focus = true; }
                    }
                }
            }

            ListModel { id: historyModel }

            SuggestionContainer { 
                id: suggestionContainer
            } // end of suggestionContainer

            DropShadow {
                z: 3
                visible: (urlText.focus && historyModel.count > 0)
                anchors.fill: source
                cached: true;
                horizontalOffset: 3;
                verticalOffset: 3;
                radius: 12.0;
                samples: 16;
                color: "#80000000";
                smooth: true;
                source: suggestionContainer;
            }
	
            MouseArea { 
                id: overlayMouseArea 
                anchors.fill: parent 
                anchors.topMargin: 65 
                anchors.leftMargin: 0
                z: 3
                enabled: (root.state == "setting" || root.state == "popup" || root.state == "drawer" )
                onClicked: { 
                    //console.log('overlayMouseArea clicked')
                    if ( root.state == "setting" || root.state == "drawer") 
                        root.state = "normal"
                }
            } 
            Rectangle { 
                id: urlProgressBar 
                height: 4
                visible: (hasTabOpen && Tab.itemMap[currentTab].loadProgress < 100)
                width: (typeof(Tab.itemMap[currentTab]) !== "undefined") ? parent.width * (Tab.itemMap[currentTab].loadProgress/100) : 0
                anchors { bottom: naviBar.bottom; left: parent.left }
                color: "#bf616a" 
                z: 1
            }

            Rectangle { 
                width: 10; height: 10; z: 1; color: "#989897"; anchors { top: parent.top; right: setting.left } 
            }
            Rectangle { 
                width: 24; height: 24; z: 1; color: "#f7f6f4"; radius: 12; anchors { top: parent.top; right: setting.left }
            }
            Rectangle { 
                width: setting.width - 20; height: 65 + 25; color: "#989897"; z: 1;
                anchors { top: parent.top; right: parent.right; topMargin: -25 } radius: 22 
            }

            // setting sheet 
            Rectangle {
                id: settingSheet
                width: setting.width - 20 
                height: 660
                color: '#989897'
                anchors { right: parent.right; }
                y: -height - 20
                radius: 22
                z: 3 

                BlurPanel {
                    target: Tab.itemMap[currentTab]
                    property variant targetY: parent.y
                    anchors.fill: parent
                    anchors.topMargin: 85
                }

                // volume bar
                Rectangle{
                    id: volumeBar
                    anchors{
                        topMargin: 95
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    width: parent.width - 20
                    height: 30
                    color: "transparent"

                    Image {
                        id: volumeMuted
                        source: "icons/audio-volume-muted-symbolic.svg"
                        width: 30; height: width; sourceSize.width: width*2; sourceSize.height: height*2;
                        anchors{
                            left: parent.left
                            leftMargin: 15
                            verticalCenter: parent.verticalCenter
                        }
                    }

                    Image {
                        id: volumeHigh
                        source: "icons/audio-volume-high-symbolic.svg"
                        width: 30; height: width; sourceSize.width: width*2; sourceSize.height: height*2;
                        anchors{
                            right: parent.right
                            rightMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                    }

                    Slider { 
                        id: volumeSlider
                        from: 0; to: 100; stepSize: 20; value: 80; 
                        anchors { left: volumeMuted.right; right: volumeHigh.left; verticalCenter: parent.verticalCenter; margins: 10 } 
                        background: Rectangle {
                            x: volumeSlider.leftPadding
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 4
                            width: volumeSlider.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: "#bdbebf"

                            Rectangle {
                                width: volumeSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#4875E2"
                                radius: 2
                            }
                        }
                        onValueChanged: {
                            if (value == 0)
                                audio.source = "icons/audio-volume-muted-symbolic.svg"
                            else if (value <= 60)
                                audio.source = "icons/audio-volume-low-symbolic.svg"
                            else if (value <= 80)
                                audio.source = "icons/audio-volume-medium-symbolic.svg"
                            else
                                audio.source = "icons/audio-volume-high-symbolic.svg"
                            setAudioVolume(value);
                        }
                    }
                }

                // orientation lock
                Rectangle{
                    id: orientationLock
                    anchors{
                        topMargin: 20
                        top: volumeBar.bottom
                        left: parent.left
                        right: parent.right
                    }

                    width: parent.width - 25
                    height: 40
                    color: "transparent"

                    Text {
                        text: "Orientation Lock"
                        color: "white"
                        anchors{
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            leftMargin: 15
                        }
                        font.pointSize: 9
                    }

                    Rectangle{
                        id: toggleTrack
                        anchors{
                            verticalCenter: parent.verticalCenter
                            right: parent.right
                            rightMargin: 20
                        }
                        width: 60
                        height: 30
                        radius: 15
                        color: sensorEnabled ? "grey" : "#4875E2"

                        Rectangle{
                            id: toggleThumb
                            anchors{
                                top: parent.top
                                bottom: parent.bottom
                                right: parent.right
                            }
                            width: 30
                            height: 30
                            radius: 15
                            color: "white"

                            states: [
                                State {
                                    name: "enabled"
                                    AnchorChanges { target: toggleThumb; anchors.left: undefined; anchors.right: parent.right }
                                },
                                State {
                                    name: "disabled"
                                    AnchorChanges { target: toggleThumb; anchors.left: parent.left; anchors.right: undefined }
                                }
                            ]
                        }

                        MouseArea{
                            anchors.fill: parent
                            onClicked: {
                                sensorEnabled = !sensorEnabled
                                if (sensorEnabled)
                                    toggleThumb.state = "enabled"
                                else
                                    toggleThumb.state = "disabled"
                            }
                        }
                    }
                }

                Rectangle{
                    id: brightnessControl
                    anchors{
                        topMargin: 20
                        top: orientationLock.bottom
                        left: parent.left
                        right: parent.right
                    }

                    width: parent.width - 25
                    height: 40
                    color: "transparent"

                        Text {
                            id: brightnessIcon
                            text: "\uf0eb"
                            font.family: fontAwesome.name
                            color: "white"
                            anchors{
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                leftMargin: 20
                            }
                            font.pointSize: 10
                        }
                        Slider { 
                            id: brightnessSlider
                            from: 0; to: 50; stepSize: 10; value: 50; 
                            anchors {
                                left: brightnessIcon.right
                                leftMargin: 15
                                right: parent.right
                                rightMargin: 15
                                verticalCenter: parent.verticalCenter

                            }
                            background: Rectangle {
                                x: brightnessSlider.leftPadding
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                implicitWidth: 200
                                implicitHeight: 4
                                width: brightnessSlider.availableWidth
                                height: implicitHeight
                                radius: 2
                                color: "#bdbebf"

                                Rectangle {
                                    width: brightnessSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: "#4875E2"
                                    radius: 2
                                }
                            }
                            onValueChanged: {
                                setScreenBrightness(50+value)
                            }
		                }
                }

                // separator
                Rectangle{
                    id: separator
                    anchors{
                        right: parent.right
                        left:parent.left
                        top: brightnessControl.bottom
                        topMargin: 20
                        leftMargin: 20; rightMargin: 20
                    }
                    height: 1
                    color: "#ECEFF4"
                }

                // wifi scan result 
                ListView {
                    id: wifiListView
                    visible: root.state == "setting" 
                    clip: true
                    anchors {
                        bottomMargin: 15
                        topMargin: 15
                        top: separator.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    model: networkingModel
                    delegate: Rectangle {
                        height: 45
                        width: wifiListView.visible ? wifiListView.width : 0
                        color: 'transparent' 
                        Row {
                            width: parent.width - 40 
                            height: parent.height
                            spacing: 10

                            Rectangle { 
                                width: 30
                                height: 20
                                color: 'transparent'
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    font.family: fontAwesome.name 
                                    font.pixelSize: 12
                                    text: (modelData.state == "online" || modelData.state == "ready") ? "\uf00c" : ""
                                    color: "white"
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                text: (modelData.name == "") ? "[Hidden Wifi]" : modelData.name
                                color: "white"
                                elide: Text.ElideRight
                                width: 230
                                anchors.verticalCenter: parent.verticalCenter
                                font.pointSize: 9
                            }
                        }
                        Row {
                            anchors {
                                right: parent.right
                                top: parent.top
                                bottom: parent.bottom
                                rightMargin: 30
                            }
                            width: 50
                            spacing: 10
                            Rectangle {
                                width: 20
                                height: 20 
                                color: 'transparent'
                                anchors.verticalCenter: parent.verticalCenter
                                Image { 
                                    width: 20; height: width; sourceSize.width: width*2; sourceSize.height: height*2;
                                    source: (modelData.security[0] == "none") ? "" : "icons/network-wireless-encrypted-symbolic.svg"
                                }
                            }
                            Image {
                                width: 20; height: width; sourceSize.width: width*2; sourceSize.height: height*2;
                                source: if (modelData.strength >= 55 ) { return "icons/network-wireless-signal-excellent-symbolic.svg" }
                                else if (modelData.strength >= 50 ) { return "icons/network-wireless-signal-good-symbolic.svg" }
                                else if (modelData.strength >= 45 ) { return "icons/network-wireless-signal-ok-symbolic.svg" }
                                else if (modelData.strength >= 30 ) { return "icons/network-wireless-signal-weak-symbolic.svg" }
                                else { return "icons/network-wireless-signal-none-symbolic.svg" }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (modelData.state == "idle" || modelData.state == "failure") {
                                    networkingModel.networkName = modelData.name 
                                    modelData.requestConnect()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: setting  
                color: '#989897' //"#2E3440"
                width: 360 + 20 
                height: 65
                anchors {
                    top: parent.top
                    right: parent.right
                    rightMargin: -20
                }
                radius: 22
                z: 4 

                Row { 
                    id: statusAreaBar 
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 15
                        rightMargin: 20 + 15
                    }
                    height: 45 
                    spacing: 10

                    Text { 
                        font.pointSize: 8
                        text: (batteryCharging) ? "charging" : batteryPercentage + "%"
                        anchors.topMargin: 5
                        anchors.rightMargin: (batteryCharging) ? -5 : -2 
                        anchors.top: parent.top 
                        color: 'white'
                    }

                    // battery 
                    Image {
                        source: if (batteryCharging) { "icons/battery-full-charged-symbolic.svg" } 
                            else if (batteryPercentage >= 80) { "icons/battery-full-symbolic.svg" } 
                            else if (batteryPercentage >= 50) { "icons/battery-good-symbolic.svg" } 
                            else if (batteryPercentage >= 30) { "icons/battery-low-symbolic.svg" } 
                            else if (batteryPercentage >= 20) { "icons/battery-caution-symbolic.svg" } 
                            else { "icons/battery-empty-symbolic.svg" } 
                        width: 34; height: width; sourceSize.width: width*2; sourceSize.height: height*2;
                    }

                    // audio
                    Image {
                        id: audio
                        source: "icons/audio-volume-medium-symbolic.svg"
                        width: 34; height: width; sourceSize.width: width*2; sourceSize.height: height*2;
                    }

                    // wifi
                    Image {
                        id: wifiIndicator
                        source: if (networkManager.state == "idle") { "icons/network-wireless-signal-none-symbolic.svg" } // no wifi connection
                            else if (networkManager.connected && networkManager.connectedWifi.strength >= 55 ) { "icons/network-wireless-signal-excellent-symbolic.svg" } 
                            else if (networkManager.connected && networkManager.connectedWifi.strength >= 50 ) { "icons/network-wireless-signal-good-symbolic.svg" } 
                            else if (networkManager.connected && networkManager.connectedWifi.strength >= 45 ) { "icons/network-wireless-signal-ok-symbolic.svg" } 
                            else if (networkManager.connected && networkManager.connectedWifi.strength >= 30 ) { "icons/network-wireless-signal-weak-symbolic.svg" } 
                            else { "icons/network-wireless-connected-symbolic.svg" } 
                        width: 34; height: width; sourceSize.width: width*2; sourceSize.height: height*2; 
                    }

                    Text {
                        id: systemClock
                        font.pointSize: 11
                        text: Qt.formatDateTime(new Date(), formatDateTimeString)
                        color: 'white'
                        anchors.leftMargin: 5
                        Timer { 
                            id: systemTime
                            repeat: true 
                            interval: 60000
                            running: true 
                            triggeredOnStart: true
                            onTriggered: setSystemClock();
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent 
                    drag.target: settingSheet; drag.axis: Drag.YAxis; drag.minimumY: -535; drag.maximumY: 0
                    onPressAndHold: {
                        screenshotTimer.start();
                    }
                    onClicked: { 
                        if (settingSheet.y > -535) { root.state = "normal" } else { root.state = "setting" }
                    } 
                    onReleased: { 
                        if (settingSheet.y > -535) { root.state = "setting" } else { root.state = "normal" }
                    }
                }
                Timer {
                    id: screenshotTimer
                    interval: 3000
                    running: false
                    repeat: false
                    onTriggered: {
                        root.grabToImage(function(result) {
                            var fileName = Qt.formatDateTime(new Date(), "yyyy-MM-dd-hh-mm-ss") + ".png";
                            result.saveToFile("/home/pi/Pictures/" + fileName);
                            console.log("Screenshot: " + fileName);
                            notification.showNotification("Screenshot saved to:\n" + fileName);
                        });
                    }
                }
            }

            // popup 
            Item {
                id: popupScreen
                z: 5 
                visible: root.state == "popup"
                anchors.fill: parent

                Rectangle {
                    id: overlay 
                    anchors.fill: parent
                    color: 'grey'
                    opacity: 0.4
                    MouseArea { anchors.fill: parent; enabled: popupScreen.visible }
                }

                Rectangle {
                    id: dialog
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 50 
                    radius: 15; 
                    width: 600; height: 300
                    color: 'white'

                    Text { 
                        id: dialogTitle
                        anchors {
                            top: parent.top
                            topMargin: 15 
                            horizontalCenter: parent.horizontalCenter
                        }
                        text: 'Enter the password for "' + networkingModel.networkName + '"'
                        wrapMode: Text.Wrap
                        font.pointSize: 9
                    }
                    TextField {
                        id: passwordInput
                        anchors {
                            top: dialogTitle.bottom
                            horizontalCenter: parent.horizontalCenter
                            margins: 10
                            topMargin: 30
                        }
                        width: parent.width - 50
                        height: 40
                        font.pointSize: 9
                        echoMode: showPassword.checked ? TextInput.Normal : TextInput.Password
                    }
                    CheckBox { 
                        id: showPassword
                        text: qsTr("Show password") 
                        font.pointSize: 10
                        checked: false
                        anchors {
                            top: passwordInput.bottom
                            left: passwordInput.left
                            margins: 30
                            leftMargin: 10
                        }
                    }
                    Row {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom; margins: 10
                        }
                        height: 60
                        width: parent.width
                        spacing: 340
                        Rectangle {
                            height: 60
                            width: 120
                            color: 'transparent'
                            Text {
                                text: 'Cancel' 
                                font.pointSize: 10
                                anchors.centerIn: parent
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.state = "normal";
                                    userAgent.sendUserReply({});
                                    scanTimer.running = true;
                                }
                            }
                        }
                        Rectangle {
                            height: 60
                            width: 120; radius: 10
                            color: '#4875E2'
                            Text {
                                text: 'Join' 
                                font.pointSize: 10
                                font.bold: true
                                anchors.centerIn: parent
                                color: 'white'
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.state = "normal";
                                    scanTimer.running = true;
                                    userAgent.sendUserReply({"Passphrase": passwordInput.text });
                                    wifiIndicator.source = "icons/network-wireless-acquiring-symbolic.svg";
                                }
                            }
                        }
                    }
                }
            } // end of popup 


            // on-screen keyboard 
            InputPanel {
                id: inputPanel
                z: 89
                x: keyboardPosition[view.orientation].hidden_x
                y: keyboardPosition[view.orientation].hidden_y
                width: portraitMode ? 800 : 1280
                rotation: orientation
                visible: false
                onActiveChanged: visible = true

                states: State {
                    name: "visible"
                    when: inputPanel.active && root.state != "locked" && root.state != "switchoff"
                    PropertyChanges {
                        target: inputPanel
                        x: view.keyboardPosition[view.orientation].x
                        y: view.keyboardPosition[view.orientation].y
                    }
                }
                transitions: Transition {
                    id: inputPanelTransition
                    from: ""
                    to: "visible"
                    reversible: true
                    enabled: !VirtualKeyboardSettings.fullScreenMode
                    ParallelAnimation {
                        NumberAnimation {
                            properties: "x"
                            duration: 250
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            properties: "y"
                            duration: 250
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
                Binding {
                    target: InputContext
                    property: "animating"
                    value: inputPanelTransition.running
                }
            }

            // lockscreen 
            Image {
                id: lockscreen 
                visible: ( root.state == "locked" )
                source: wallpaperUrl 
                fillMode: Image.PreserveAspectCrop
                z: 6
                x: 0; y: 0; width: parent.width; height: parent.height 
                MouseArea {
                    id: lockscreenMosueArea
                    anchors.fill: parent 
                    enabled: !screenLocked
                    onEnabledChanged: {
                        if (enabled && root.state == "locked" ) { idleTimer.start() }
                    }
                    drag.target: lockscreen; drag.axis: Drag.YAxis; drag.maximumY: 0
                    onReleased: { 
                        if (lockscreen.y > -480) { bounce.restart(); } else { root.state = "normal"; lockscreen.y = 0; sensorEnabled = true; } 
                        idleTimer.restart();
                    } 
                }
                Timer {
                    id: idleTimer
                    running: false; interval: 8000;
                    onTriggered: { 
                        if (root.state == "locked") { // dim the screen after 8s idle 
                            screenLocked = true; 
                            turnScreenOff();
                        }
                    } 
                }
                NumberAnimation { id: bounce; target: lockscreen; properties: "y"; to: 0; easing.type: Easing.InOutQuad; duration: 200 }
                Text { 
                    id: lockscreenTime
                    text: Qt.formatDateTime(new Date(), "HH:mm"); color: wallpaperFontColor; font.pointSize: 22; 
                    anchors { left: parent.left; bottom: lockscreenDate.top; leftMargin: 30; bottomMargin: 5 }
                }
                Text { 
                    id: lockscreenDate
                    text: Qt.formatDateTime(new Date(), "dddd, MMMM d"); color: wallpaperFontColor; font.pointSize: 14; 
                    anchors { left: parent.left; bottom: parent.bottom; margins: 30 }
                }
            }

            PowerOffMenu { id: powerOffMenu }
        } // end of content  

        // notification
        Item {
            id: notification
            width: notificationContainer.width + 55
            height: notificationContainer.height + 55
            anchors.horizontalCenter: parent.horizontalCenter
            y: -160
            visible: (showAnimation.running || hideAnimation.running || notificationTimer.running)
            Rectangle {
                id: notificationContainer
                width: 480
                height: 100
                radius: 20
                color: "#3B4252"
                anchors.centerIn: parent
                z: 10

                Text {
                    id: notificationText
                    text: ""
                    color: "#D8DEE9"
                    anchors{
                        centerIn: parent
                    }
                    font.pointSize: 9
                }
            }

            NumberAnimation {
                id: showAnimation
                target: notification
                properties: "y"
                to: 10
                duration: 500
            }

            NumberAnimation {
                id: hideAnimation
                target: notification
                properties: "y"
                to: -160
                duration: 500
            }

            Timer{
                id: notificationTimer
                interval: 3000
                running: false
                onTriggered: {
                    hideAnimation.start();
                }
            }

            function showNotification(msg){
                notificationText.text = msg;
                showAnimation.start();
                notificationTimer.start();
            }
        }
        DropShadow {
            z: 10
            visible: notification.visible
            anchors.fill: source
            cached: true;
            horizontalOffset: 3;
            verticalOffset: 3;
            radius: 12.0;
            samples: 16;
            color: "#aa000000";
            smooth: true;
            source: notification;
        }

        state: "normal" 

        states: [
            State {
                name: "setting"
                PropertyChanges { target: settingSheet; y: 0 } 
            },
            State { name: "locked" }, 
            State { name: "popup" }, 
            State { name: "switchoff" }, 
            State{
                name: "drawer"
                PropertyChanges { target: content; anchors.leftMargin: Tab.DrawerWidth }
            },
            State {
                name: "normal"
                PropertyChanges { target: content; anchors.leftMargin: 0 }
                PropertyChanges { target: settingSheet; y: -settingSheet.height + 65 }
            }
        ]

        transitions: [
            Transition {
                to: "*"
                NumberAnimation { target: settingSheet; properties: "y"; duration: 400; easing.type: Easing.InOutQuad; }
                NumberAnimation { target: content; properties: "anchors.leftMargin"; duration: 300; easing.type: Easing.InOutQuad; }
            }
        ]
    } // end of root 

} // end of view Window 
