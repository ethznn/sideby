# Sideby

Switch tasks. Your screens follow.

[Website](https://ethznn.github.io/sideby/) · [한국어](README.ko.md)

Sideby connects the macOS Spaces you use together, so your displays move to the next task in one action. Save different window layouts on the same desktop and recognize your next workspace in a visual gallery.

**Distribution in preparation.** Public app downloads are temporarily paused. Availability will be announced on the website when distribution resumes.

## What Sideby does

- Switch connected Spaces across your displays together.
- Save different window positions and sizes on the same ordinary desktop.
- Choose a workspace from large screen previews with **⌥⇧Space**.
- Edit Space connections from the menu bar.

Sideby supports Apple silicon Macs running macOS 14 or later. Layout restoration uses windows that are still available on the destination desktop. It does not reopen apps, documents, or tabs, and it does not move windows out of another Space. Full-screen apps switch Spaces only. Layout restoration supports Stage Manager off and remains subject to each app's window-size restrictions.

## Privacy and permissions

Accessibility supports configured global input and window-layout restoration. Screen Switching access permits desktop transitions; some paths also need System Events Automation. Screen Recording is optional and is requested when you allow previews.

Ordinary previews stay in memory. Explicitly saved setup images and window information stay on your Mac. Disabling previews does not remove saved setup images. Images and typed input are not uploaded.

## This repository

This repository contains the public product website, not the application source or app installers. The MIT license in this repository covers its website source. See [website maintenance](docs/WEBSITE.md) for local build and verification instructions.
