package com.faster.backend.entity;

import java.util.function.BiConsumer;
import java.util.function.Function;

/**
 * The 4 driver document types (profile photo, national ID, license
 * front/back) — single source of truth for which User field each one
 * reads/writes. This used to be duplicated 3 ways across
 * DriverController and AdminController: a raw String allow-list
 * declared independently in each class, a docType-string -> User-getter
 * switch (viewing), and a docType-string -> User-setter switch
 * (uploading). Adding a 5th document type (e.g. vehicle registration)
 * meant editing the same enumeration correctly in all of those places,
 * or the upload and view/admin-view endpoints could silently disagree
 * about which types are valid.
 */
public enum DriverDocumentType {
    PROFILE_PHOTO(User::getDriverPhotoUrl, User::setDriverPhotoUrl),
    NATIONAL_ID(User::getNationalIdUrl, User::setNationalIdUrl),
    LICENSE_FRONT(User::getDriverLicenseFrontUrl, User::setDriverLicenseFrontUrl),
    LICENSE_BACK(User::getDriverLicenseBackUrl, User::setDriverLicenseBackUrl);

    private final Function<User, String> getter;
    private final BiConsumer<User, String> setter;

    DriverDocumentType(Function<User, String> getter, BiConsumer<User, String> setter) {
        this.getter = getter;
        this.setter = setter;
    }

    public String get(User driver) {
        return getter.apply(driver);
    }

    public void set(User driver, String relativePath) {
        setter.accept(driver, relativePath);
    }

    /** Case-insensitive lookup; returns null instead of throwing for an unknown value. */
    public static DriverDocumentType fromString(String raw) {
        if (raw == null) return null;
        try {
            return valueOf(raw.toUpperCase());
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
