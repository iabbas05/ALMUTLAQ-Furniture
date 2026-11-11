# Physical acceptance checklist

Status: NOT RUN on this checkpoint. Record exact commit, APK/IPA checksum, date, device/OS, tester and observed results. Never tick a device check based only on CI.

## Phone

- [ ] Arabic and English labels, RTL/LTR, Arabic/Persian/Latin numeric input, large text, 320/390/768 logical-pixel layouts.
- [ ] Sofa and chair visibly render as furniture in 3D and a detailed plan, not plain rectangles. Opening positions agree in both views.
- [ ] Room width 4 to 5 m changes the room only. Measured sofa width remains 2.10 m and chair width 0.84 m.
- [ ] Rotate 15/90/180 degrees, drag to every wall, undo/redo, replace a piece, and restore a named design. No negative clearance after an accepted placement.
- [ ] Pair the phone over USB or configured HTTPS service, review the target revision, send the design, and observe an actual PICO applied-revision acknowledgement.
- [ ] iPhone product preview opens both bundled USDZ files without a hosted AR website. Translation/rotation work. Scaling stays locked. Test without network after installation.
- [ ] Android web AR opens the configured published HTTPS page with the selected SKU and current language. Unknown SKUs show no incorrect sofa.
- [ ] Cached catalogue is labelled appropriately offline. Verify actual fetched catalogue count, pictures/descriptions/variants and price units against each website. Full coverage is not assumed.

## iPhone with LiDAR

- [ ] Supported hardware shows scan. Unsupported hardware keeps manual input available.
- [ ] Camera denial has a usable recovery path. Cancelling a scan preserves the old design.
- [ ] Rectangular room scan produces draft measurements and requires review before applying.
- [ ] Nonrectangular scan does not silently replace the room by its bounding rectangle.
- [ ] Compare each scanned wall with a tape/laser. Record maximum error. Verify openings manually.

## PICO 4 Ultra

- [ ] Build/install the separate Unity APK. Record Editor, PICO SDK pin and headset OS.
- [ ] Floor tracking and viewpoint height agree with the physical floor. No unexpected scale changes.
- [ ] Measure sofa width/depth/height 2.10/1.03/1.00 m and chair 0.84/0.95/0.94 m. Record the observed error in millimetres and placement method.
- [ ] After five minutes of head movement, record drift relative to the same floor markers. Do not label tracking accurate before measuring it.
- [ ] Record average/minimum frame rate and visible stutter for 1/10/50 items using the headset performance tools. Performance target must match the selected headset refresh rate.
- [ ] Headset stick movement and rotation sync back to the panel. A staff edit conflict reloads the accepted revision rather than overwriting it.
- [ ] Invalid room/model/checksum leaves the previous full scene visible and does not ACK the rejected revision.
- [ ] USB disconnect/reconnect preserves the scene, re-establishes reverse and eventually applies/ACKs the latest revision.
- [ ] Upload a valid dimension-matching static GLB, preview and publish it. Confirm no reinstall is needed and existing saved designs retain their old model version.

## Records and delivery

- [ ] Customer permission required, name/phone stay off headset scene documents, one-record export contains only the selected TEST customer.
- [ ] Retention setting persists. Expired TEST rows disappear after restart. Delete/exported-backup handling explained to the operator.
- [ ] Android APK installs on the target phone. iOS unsigned IPA is correctly signed before any normal installation test.
- [ ] Manufacturer approves shape, fabric and colour. Reconstructed demo geometry is not treated as approved CAD.
