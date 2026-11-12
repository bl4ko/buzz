use tauri::image::Image;

pub(crate) fn icon() -> Image<'static> {
    const SIZE: u32 = 44;
    const SAMPLES_PER_AXIS: u32 = 4;
    const UNITS_PER_PIXEL: f32 = 840.0 / SIZE as f32;
    const LEFT: f32 = 92.0;
    const TOP: f32 = 31.0;
    const CENTER: (f32, f32) = (512.0, 468.0);
    const MOUNTAIN: [(f32, f32); 3] = [(130.0, 940.0), (512.0, 236.0), (894.0, 940.0)];
    fn edges(polygon: &[(f32, f32)]) -> impl Iterator<Item = ((f32, f32), (f32, f32))> + '_ {
        polygon
            .iter()
            .copied()
            .zip(polygon.iter().copied().cycle().skip(1))
    }

    fn polygon_contains(polygon: &[(f32, f32)], x: f32, y: f32) -> bool {
        edges(polygon).fold(false, |inside, ((x1, y1), (x2, y2))| {
            if (y1 > y) != (y2 > y) && x < (x2 - x1) * (y - y1) / (y2 - y1) + x1 {
                !inside
            } else {
                inside
            }
        })
    }

    fn mark_contains(x: f32, y: f32) -> bool {
        let radius = (x - CENTER.0).hypot(y - CENTER.1);
        (310.0..=378.0).contains(&radius) || radius <= 284.0 && polygon_contains(&MOUNTAIN, x, y)
    }

    let mut rgba = vec![0; (SIZE * SIZE * 4) as usize];
    let samples = SAMPLES_PER_AXIS * SAMPLES_PER_AXIS;

    for pixel_y in 0..SIZE {
        for pixel_x in 0..SIZE {
            let mut covered_samples = 0;
            for sample_y in 0..SAMPLES_PER_AXIS {
                for sample_x in 0..SAMPLES_PER_AXIS {
                    let x = LEFT
                        + (pixel_x as f32 + (sample_x as f32 + 0.5) / SAMPLES_PER_AXIS as f32)
                            * UNITS_PER_PIXEL;
                    let y = TOP
                        + (pixel_y as f32 + (sample_y as f32 + 0.5) / SAMPLES_PER_AXIS as f32)
                            * UNITS_PER_PIXEL;
                    if mark_contains(x, y) {
                        covered_samples += 1;
                    }
                }
            }

            let index = ((pixel_y * SIZE + pixel_x) * 4) as usize;
            rgba[index + 3] = (covered_samples * u8::MAX as u32 / samples) as u8;
        }
    }

    Image::new_owned(rgba, SIZE, SIZE)
}

#[cfg(test)]
mod tests {
    use super::icon;

    #[test]
    fn tray_icon_masks_the_olympus_mark() {
        let icon = icon();
        let alpha = |x: u32, y: u32| icon.rgba()[((y * icon.width() + x) * 4 + 3) as usize];

        assert_eq!((icon.width(), icon.height()), (44, 44));
        assert_eq!(alpha(0, 0), 0);
        assert_eq!(alpha(3, 22), u8::MAX);
        assert_eq!(alpha(10, 20), 0);
        assert_eq!(alpha(20, 29), u8::MAX);
        assert_eq!(alpha(34, 6), 0);
    }
}
