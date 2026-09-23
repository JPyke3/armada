//! Helpers for adjusting RGB saturation without converting color spaces.

/// Apply an HSV-style saturation adjustment directly to RGB channels.
pub(crate) fn rgb_after_saturation([red, green, blue]: [u8; 3], saturation: u8) -> [u8; 3] {
    let highest_channel: u16 = u16::from(red.max(green).max(blue));
    let saturation: u16 = u16::from(saturation.min(100));
    let desaturation: u16 = 100 - saturation;

    let adjust = |channel: u8| -> u8 {
        let channel: u16 = u16::from(channel);
        let gap: u16 = highest_channel - channel;
        let movement: u16 = (gap * desaturation + 50) / 100;
        (channel + movement) as u8
    };

    [adjust(red), adjust(green), adjust(blue)]
}

#[cfg(test)]
mod tests {
    use super::rgb_after_saturation;

    #[test]
    fn preserves_full_saturation() {
        assert_eq!(rgb_after_saturation([255, 165, 0], 100), [255, 165, 0]);
    }

    #[test]
    fn desaturates_red_halfway() {
        assert_eq!(rgb_after_saturation([255, 0, 0], 50), [255, 128, 128]);
    }

    #[test]
    fn desaturates_orange_to_white_at_zero() {
        assert_eq!(rgb_after_saturation([255, 165, 0], 0), [255, 255, 255]);
    }
}
