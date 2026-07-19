from PIL import Image, ImageDraw
S = 1024
img = Image.new("RGB", (S, S), (11, 81, 55))  # deep green #0B5137
d = ImageDraw.Draw(img)
white = (255, 255, 255)

W = 46  # stroke width
# Rising trend line (zig-zag up), centered in the canvas.
pts = [(210, 690), (420, 500), (600, 600), (790, 360)]
d.line(pts, fill=white, width=W, joint="curve")
r = W // 2
for (x, y) in pts:
    d.ellipse([x-r, y-r, x+r, y+r], fill=white)

# Arrowhead at the top-right terminus, pointing up-right along the last segment.
tip = (858, 300)
d.polygon([tip, (tip[0]-150, tip[1]+18), (tip[0]-18, tip[1]+150)], fill=white)

# Baseline + left axis, subtle, to read as a chart.
axis = (240, 240, 240)
d.line([(180, 760), (860, 760)], fill=axis, width=18)
d.line([(180, 300), (180, 760)], fill=axis, width=18)

img = img.convert("RGB")
out = "/home/user/Wealth/ios/Wealth/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
img.save(out, "PNG")
chk = Image.open(out)
print("size", chk.size, "mode", chk.mode)
