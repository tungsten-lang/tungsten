# Amazon return labels for Rollo

`print-label FILE.pdf` extracts the mailing label from the Amazon Online Return Center PDF and submits it to the `Rollo_X1040` CUPS queue on 4×6 stock. This queue was added for the Wi-Fi Rollo using IPP Everywhere. The default printer is not changed.

To inspect before printing:

```sh
print-label ~/Downloads/'Online Return Center.pdf' --output ~/Downloads/label-4x6.pdf
open ~/Downloads/label-4x6.pdf
```

The output must not already exist. The output is a one-page 4×6 PDF, rotated upright, retaining the original image at its full resolution with a small white margin. The separate return authorization slip is not printed; follow Amazon's instructions for that slip.

Override the destination with `--printer CUPS_QUEUE` or `ROLLO_PRINTER=CUPS_QUEUE`. Find queues using `lpstat -p`. The printer must have 4×6 labels loaded. Inspect the first physical print for complete text, unclipped bars and quiet zones; confirm the carrier can scan it before relying on it.

This supports the observed Amazon layout, where the mailing label is a single embedded, landscape 3:2 image of at least 900×600 pixels. It refuses PDFs with zero or multiple matching images. Amazon and carriers can use other layouts; those will need additional detection work. It does not print or extract the separate authorization slip, and does not guarantee that a different PDF's matching image is a mailing label. Check unfamiliar layouts with `--output` first.

Requirements: macOS, Tungsten, Apple clang, and Poppler `pdfimages` at `/opt/homebrew/bin/pdfimages` (`brew install poppler`). Rebuild after editing:

```sh
cd ~/tungsten
clang -O2 apps/print-label/image-native.c -framework CoreFoundation -framework CoreGraphics -framework ImageIO -o apps/print-label/image-native
bin/tungsten -o apps/print-label/print-label apps/print-label/print-label.w
bin/tungsten -o apps/print-label/bridge-job apps/print-label/bridge-job.w
```

The Tungsten command selects the embedded image, thresholds pixels when requested, computes the 4×6 layout, and invokes the small `image-native` helper for macOS ImageIO and CoreGraphics operations. The Tungsten `bridge-job` executable handles the IPP job and notifications. Both executables locate their companions beside their own resolved binary, so they can be moved together and invoked through symlinks without relying on a particular home directory. Keep `print-label`, `bridge-job`, and `image-native` together. macOS LaunchAgent configuration requires absolute installed paths; update its paths if moving the installation. The temporary image files are stored in a private directory and removed after processing. CUPS handles print jobs according to its own spool retention settings.

## Virtual printer

Choose **Amazon Return Label Printer** from Safari's print dialog while viewing the Amazon return page. Use the normal letter-sized page and print one copy; the bridge extracts the embedded mailing label and submits a 4×6 job to `Rollo_X1040`. The same layout limitations apply as for the command. The authorization slip is separate.

The queue connects to an IPP service listening on localhost port 18631. The per-user LaunchAgent `~/Library/LaunchAgents/com.erik.amazon-return-label-printer.plist` starts it at login and restarts it if it exits; the user must be logged in. Its private working directory and log are in `~/Library/Application Support/Print Label/`. If extraction or submission fails, the bridge records the error in `bridge.log` and attempts a desktop notification. A successful virtual job means the label was submitted to the Rollo queue, not necessarily that paper has printed. Check the Rollo queue for downstream printer errors.

The Mac virtual queue receives PDF only and rejects multiple copies. Remove the queue with `lpadmin -x Amazon_Return_Label_Printer`; stop the service with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.erik.amazon-return-label-printer.plist` and delete that plist to prevent it starting again. This does not remove the Rollo queue.

## iPhone / AirPrint

Choose **Amazon Return Label Printer** in the iPhone print dialog. The Mac must be awake, logged in, and on the same network as the iPhone and Rollo. The AirPrint service starts at login using `~/Library/LaunchAgents/com.erik.amazon-return-label-airprint.plist`; its log and spool are in `~/Library/Application Support/Print Label/`.

The service advertises PDF and Apple raster to permit AirPrint discovery, but the label extractor currently handles **PDF only**. The tested iPhone Safari return-label job arrived as a PDF and extracted successfully. If an iPhone or app sends raster instead, the job fails rather than printing an incorrect label; check `airprint.log` and the Mac notification. A successful bridge job means the label was submitted to the Rollo queue, not necessarily that it printed.

This network service listens on all network interfaces and does not require a password: other devices that can reach the Mac can submit print jobs. AirPrint discovery normally stays on the local network. Stop it with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.erik.amazon-return-label-airprint.plist`; delete that plist to prevent it starting again. The Mac-only virtual queue remains independent.

For iPhone jobs, the AirPrint service sets `LABEL_THRESHOLD=128` to convert the extracted label to black and white before printing. iOS may resample the image when preparing its PDF; this improves contrast but cannot restore lost image detail. Command-line and Mac-only jobs do not use this setting. If needed, remove the variable from the AirPrint LaunchAgent and restart it to disable the cleanup.

When an AirPrint job requests Best/High or Draft quality, the bridge passes that quality setting to the Rollo queue. The Rollo queue's default media type is Labels and the bridge requests 4×6 media. These settings cannot recover image detail absent from the iPhone's PDF.

The iPhone-facing service advertises High as the IPP quality default. macOS's `ippeveprinter` has no supported option to change that default alongside its format list, so the service runs an ad-hoc signed copy of the macOS executable with the small `airprint-quality.c` interposition library. It changes only the `print-quality-default` attribute; the separate Rollo queue also defaults to High. The generated binary and library are ignored by Git. To rebuild after a macOS upgrade or from a fresh checkout on this Apple Silicon Mac:

```sh
cd ~/tungsten
clang -arch arm64e -dynamiclib -Wno-deprecated-declarations -o apps/print-label/airprint-quality.dylib apps/print-label/airprint-quality.c -lcups
cp /usr/bin/ippeveprinter apps/print-label/ippeveprinter-high
codesign --force --sign - apps/print-label/ippeveprinter-high
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.erik.amazon-return-label-airprint.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.erik.amazon-return-label-airprint.plist
```
