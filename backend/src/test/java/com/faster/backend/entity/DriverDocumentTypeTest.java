package com.faster.backend.entity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

/**
 * Full-codebase review cleanup round (2026-11) — this enum replaces a
 * driver-document-type system that was duplicated 3 ways across
 * DriverController and AdminController (a raw String allow-list, a
 * docType-string -> getter switch, and a docType-string -> setter
 * switch, each declared independently in both classes).
 */
class DriverDocumentTypeTest {

    @Test
    void fromString_isCaseInsensitive() {
        assertEquals(DriverDocumentType.PROFILE_PHOTO,
                DriverDocumentType.fromString("profile_photo"));
        assertEquals(DriverDocumentType.NATIONAL_ID,
                DriverDocumentType.fromString("National_Id"));
    }

    @Test
    void fromString_returnsNullForUnknownOrNullInput() {
        assertNull(DriverDocumentType.fromString("not_a_real_type"));
        assertNull(DriverDocumentType.fromString(null));
    }

    @Test
    void getAndSet_roundTripThroughTheCorrectUserField() {
        User driver = User.builder().build();

        DriverDocumentType.PROFILE_PHOTO.set(driver, "drivers/1/a.jpg");
        DriverDocumentType.NATIONAL_ID.set(driver, "drivers/1/b.jpg");
        DriverDocumentType.LICENSE_FRONT.set(driver, "drivers/1/c.jpg");
        DriverDocumentType.LICENSE_BACK.set(driver, "drivers/1/d.jpg");

        assertEquals("drivers/1/a.jpg", driver.getDriverPhotoUrl());
        assertEquals("drivers/1/b.jpg", driver.getNationalIdUrl());
        assertEquals("drivers/1/c.jpg", driver.getDriverLicenseFrontUrl());
        assertEquals("drivers/1/d.jpg", driver.getDriverLicenseBackUrl());

        assertEquals("drivers/1/a.jpg", DriverDocumentType.PROFILE_PHOTO.get(driver));
        assertEquals("drivers/1/b.jpg", DriverDocumentType.NATIONAL_ID.get(driver));
        assertEquals("drivers/1/c.jpg", DriverDocumentType.LICENSE_FRONT.get(driver));
        assertEquals("drivers/1/d.jpg", DriverDocumentType.LICENSE_BACK.get(driver));
    }
}
