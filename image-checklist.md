# Image Conversion Checklist

Review the converted assets visually before removing any original backup.

All four GIF sources were inspected and contain one frame only. Animated WebP conversion was therefore not required.

## General checks

- [ ] Confirm every referenced image loads on desktop and mobile.
- [ ] Confirm staff portraits retain expected crop, color, and facial detail.
- [ ] Confirm transparent images have no matte, halo, or lost alpha.
- [ ] Confirm background images have acceptable quality at full-screen size.
- [ ] Confirm static GIF conversions match their single source frame.

## Second-pass optimization

- [ ] All staff WebP assets are now 1600px high or less; verify card crops after the resize pass.
- [ ] `assets/images/staff/staff-anne-hathaway-dali.webp` - resized from 1395x2419 to 923x1600; verify portrait crop and facial detail.
- [ ] `assets/images/staff/staff-miozuki-sayuri.webp` - resized from 2160x3174 to 1089x1600; verify portrait crop and facial detail.
- [ ] `assets/images/staff/staff-elicon.webp` - dimensions retained at 1002x1327; recompressed at quality 82.
- [ ] `assets/images/staff/staff-rouye.webp` - dimensions retained at 1148x1471; recompressed at quality 82.
- [ ] `assets/images/staff/staff-wulan.webp` - dimensions retained at 878x878; recompressed at quality 82.
- [ ] `assets/images/menu/menu-kaiseki.webp` - dimensions retained at 1365x768; recompressed at quality 82.
- [ ] `assets/images/brand/brand-logo-primary.webp` - excluded from second-pass compression to protect logo edges and transparency.
- [ ] `assets/images/brand/brand-logo-green.webp` - excluded from second-pass compression to protect logo edges and transparency.
- [ ] Background images were already approximately 150KB-307KB and were not recompressed.

## Per-image checks

- [ ] `assets/images/staff/staff-coming-soon.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-miozuki-sayuri.webp` - GIF source is static (1 frame)
- [ ] `assets/images/staff/staff-gu-heihei.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-chitanda.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-jiujiu.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-zhima-zhazha.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-portrait-05.webp` - unused asset; confirm identity and future purpose; temporary filename; confirm staff name
- [ ] `assets/images/staff/staff-portrait-07.webp` - unused asset; confirm identity and future purpose; temporary filename; confirm staff name
- [ ] `assets/images/staff/staff-bodi.webp` - verify crop, color, and sharpness
- [ ] `assets/images/background/background-hero.webp` - GIF source is static (1 frame)
- [ ] `assets/images/brand/brand-logo-primary.webp` - verify transparent edges/background
- [ ] `assets/images/brand/brand-logo-green.webp` - verify transparent edges/background; unused asset; confirm identity and future purpose
- [ ] `assets/images/background/background-bamboo.webp` - GIF source is static (1 frame)
- [ ] `assets/images/menu/menu-kaiseki.webp` - verify crop, color, and sharpness
- [ ] `assets/images/background/background-garden.webp` - GIF source is static (1 frame)
- [ ] `assets/images/staff/staff-elicon.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-lina.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-yuyou.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-peipei-gafeng.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-jack.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-toast.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-fubuki.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-charles.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-anlin-hill.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-yueluo-mengshi.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-rouye.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-zilin.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-wulan.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-green-tea.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-strawberry-crepe.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-anne-hathaway-dali.webp` - verify crop, color, and sharpness
- [ ] `assets/images/staff/staff-ayou.webp` - verify crop, color, and sharpness
