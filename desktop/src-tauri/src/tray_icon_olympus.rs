use tauri::image::Image;

pub(crate) fn icon() -> Image<'static> {
    const WIDTH: u32 = 45;
    const HEIGHT: u32 = 44;
    const SAMPLES_PER_AXIS: u32 = 4;
    const UNITS_PER_PIXEL: f32 = 834.0 / HEIGHT as f32;
    const LEFT: f32 = 512.0 - WIDTH as f32 * UNITS_PER_PIXEL / 2.0;
    const TOP: f32 = 48.0;
    const BOLT_GAP: f32 = 48.0;
    const MOUNTAIN: [(f32, f32); 3] = [(110.0, 860.0), (512.0, 230.0), (914.0, 860.0)];
    const BOLT: [(f32, f32); 7] = [
        (742.0, 70.0),
        (610.0, 330.0),
        (690.0, 330.0),
        (600.0, 560.0),
        (830.0, 262.0),
        (740.0, 262.0),
        (830.0, 70.0),
    ];

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

    fn distance_to_edges(polygon: &[(f32, f32)], x: f32, y: f32) -> f32 {
        edges(polygon)
            .map(|((x1, y1), (x2, y2))| {
                let (dx, dy) = (x2 - x1, y2 - y1);
                let t = (((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
                (x - x1 - t * dx).hypot(y - y1 - t * dy)
            })
            .fold(f32::INFINITY, f32::min)
    }

    fn mark_contains(x: f32, y: f32) -> bool {
        if polygon_contains(&BOLT, x, y) {
            return true;
        }
        polygon_contains(&MOUNTAIN, x, y) && distance_to_edges(&BOLT, x, y) > BOLT_GAP
    }

    let mut rgba = vec![0; (WIDTH * HEIGHT * 4) as usize];
    let samples = SAMPLES_PER_AXIS * SAMPLES_PER_AXIS;

    for pixel_y in 0..HEIGHT {
        for pixel_x in 0..WIDTH {
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

            let index = ((pixel_y * WIDTH + pixel_x) * 4) as usize;
            rgba[index + 3] = (covered_samples * u8::MAX as u32 / samples) as u8;
        }
    }

    Image::new_owned(rgba, WIDTH, HEIGHT)
}

#[cfg(test)]
mod tests {
    use super::icon;

    #[test]
    fn tray_icon_masks_the_olympus_mark() {
        let icon = icon();
        let alpha = |x: u32, y: u32| icon.rgba()[((y * icon.width() + x) * 4 + 3) as usize];

        assert_eq!((icon.width(), icon.height()), (45, 44));
        assert_eq!(alpha(0, 0), 0);
        assert_eq!(alpha(22, 40), u8::MAX);
        assert_eq!(alpha(36, 2), u8::MAX);
    }
}
