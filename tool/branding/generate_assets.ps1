# Kurumsal kimlik rehberinin 12. sayfasındaki (%100 siyah zemin) resmi logodan uygulama varlıklarını üretir.
# Logo yeniden çizilmez; yalnızca kırpılır, ölçeklenir ve siyah zemini şeffaflığa çevrilir.
param([string]$Src, [string]$Project)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
public static class Brand {
  public static Bitmap Crop(Bitmap src, int x, int y, int w, int h) {
    return src.Clone(new Rectangle(x, y, w, h), PixelFormat.Format32bppArgb);
  }
  public static Bitmap Resize(Bitmap src, int w, int h) {
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(b)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.CompositingQuality = CompositingQuality.HighQuality;
      using (var a = new ImageAttributes()) {
        a.SetWrapMode(WrapMode.TileFlipXY);
        g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, a);
      }
    }
    return b;
  }
  // "Color to alpha": zemin rengini (bg) tamamen şeffaf yapar; kenar yumuşatmaları doğru alfaya dönüşür.
  public static void BgToAlpha(Bitmap b, int bgR, int bgG, int bgB) {
    var r = new Rectangle(0, 0, b.Width, b.Height);
    var d = b.LockBits(r, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new byte[d.Stride * b.Height];
    Marshal.Copy(d.Scan0, px, 0, px.Length);
    int[] bg = { bgB, bgG, bgR }; // BGRA sırası
    for (int i = 0; i < px.Length; i += 4) {
      if (px[i + 3] == 0) continue; // zaten şeffaf (tuval boşluğu)
      double a = 0;
      for (int c = 0; c < 3; c++) {
        double v = px[i + c], z = bg[c];
        double ac = v > z ? (v - z) / (255 - z) : (z > 0 ? (z - v) / z : 0);
        if (ac > a) a = ac;
      }
      if (a <= 0.004) { px[i] = px[i + 1] = px[i + 2] = px[i + 3] = 0; continue; }
      for (int c = 0; c < 3; c++) {
        double v = (px[i + c] - bg[c]) / a + bg[c];
        px[i + c] = (byte)Math.Max(0, Math.Min(255, Math.Round(v)));
      }
      px[i + 3] = (byte)Math.Round(a * 255);
    }
    Marshal.Copy(px, 0, d.Scan0, px.Length);
    b.UnlockBits(d);
  }
  // Görseli şeffaf kare tuvalin ortasına, genişliği contentW olacak şekilde yerleştirir.
  public static Bitmap Center(Bitmap src, int canvas, int contentW) {
    int h = (int)Math.Round((double)src.Height * contentW / src.Width);
    using (var s = Resize(src, contentW, h)) {
      var b = new Bitmap(canvas, canvas, PixelFormat.Format32bppArgb);
      using (var g = Graphics.FromImage(b)) {
        g.Clear(Color.Transparent);
        g.DrawImage(s, (canvas - contentW) / 2, (canvas - h) / 2, contentW, h);
      }
      return b;
    }
  }
}
'@

function Save($bmp, $path) {
  New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
  $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
  "{0}  {1}x{2}" -f $path.Replace($Project, '.'), $bmp.Width, $bmp.Height
}

$page = [Drawing.Bitmap]::FromFile($Src)
$bgR = 0x00; $bgG = 0x02; $bgB = 0x04   # panel zemini (%100 black)

# Dikey logo (işaret + yazı), beyaz yazılı resmi varyasyon
$logo = [Brand]::Crop($page, 1038, 1404, 1383, 1081)
# İşaret (küre), dikey logonun üst kısmı
$mx = 1438; $my = 1402; $mw = 585; $mh = 585   # küre işareti
$mark = [Brand]::Crop($page, $mx, $my, $mw, $mh)
$page.Dispose()

# 1) branding/: tam çözünürlüklü kaynaklar
$full = $logo.Clone(); [Brand]::BgToAlpha($full, $bgR, $bgG, $bgB); Save $full "$Project\branding\logo_vertical_white.png"
$fullMark = $mark.Clone(); [Brand]::BgToAlpha($fullMark, $bgR, $bgG, $bgB); Save $fullMark "$Project\branding\mark.png"

# 2) Flutter varlıkları
$a = [Brand]::Resize($logo, 720, [int][Math]::Round(1081 * 720 / 1383)); [Brand]::BgToAlpha($a, $bgR, $bgG, $bgB)
Save $a "$Project\assets\branding\logo_vertical_white.png"
$m = [Brand]::Resize($mark, 192, [int][Math]::Round($mh * 192 / $mw)); [Brand]::BgToAlpha($m, $bgR, $bgG, $bgB)
Save $m "$Project\assets\branding\mark.png"

# 3) Android: adaptive icon ön katmanı (108dp @xxxhdpi = 432px; küre 60dp = 240px, 66dp güvenli alan içinde)
$fg = [Brand]::Center($mark, 432, 240)
$res = "$Project\android\app\src\main\res"
# Center() şeffaf tuvale siyah zeminli küreyi koyar; zemini sonra kaldır
[Brand]::BgToAlpha($fg, $bgR, $bgG, $bgB); Save $fg "$res\drawable-nodpi\ic_launcher_foreground.png"

# 4) Android 12+ splash ikonu (arka plansız ikon: 288dp tuval, içerik 192dp çemberde; küre 160dp)
$sp = [Brand]::Center($mark, 1152, 640); [Brand]::BgToAlpha($sp, $bgR, $bgG, $bgB)
Save $sp "$res\drawable-nodpi\splash_icon.png"

# 5) Android 8–11 splash: tam dikey logo, 200dp genişlik @xxxhdpi
$sl = [Brand]::Resize($logo, 800, [int][Math]::Round(1081 * 800 / 1383)); [Brand]::BgToAlpha($sl, $bgR, $bgG, $bgB)
Save $sl "$res\drawable-nodpi\splash_logo.png"
