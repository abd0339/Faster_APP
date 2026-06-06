package com.faster.backend.service;

import lombok.RequiredArgsConstructor;
import org.springframework.data.geo.Distance;
import org.springframework.data.geo.GeoResults;
import org.springframework.data.geo.Metrics;
import org.springframework.data.geo.Point;
import org.springframework.data.redis.connection.RedisGeoCommands;
import org.springframework.data.redis.core.GeoOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.domain.geo.GeoReference;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

@Service
@RequiredArgsConstructor
public class LocationService {

    private final RedisTemplate<String, Object> redisTemplate;

    // ─── Redis key patterns ───────────────────────────
    private static final String GEO_KEY_PACKAGE = "geo:drivers:PACKAGE";
    private static final String GEO_KEY_PEOPLE  = "geo:drivers:PEOPLE";
    private static final String GEO_KEY_HYBRID  = "geo:drivers:HYBRID";
    private static final String DRIVER_STATUS   = "driver:status:";
    private static final String DRIVER_MODE     = "driver:mode:";

    // ─── Typed GeoOperations helper ───────────────────
    // RedisTemplate<String, Object> cannot directly call
    // .search() — we cast opsForGeo() to the typed version
    @SuppressWarnings("unchecked")
    private GeoOperations<String, String> geoOps() {
        return (GeoOperations<String, String>)
            (GeoOperations<?, ?>) redisTemplate.opsForGeo();
    }

    // ─── Driver goes ONLINE ───────────────────────────
    public void driverOnline(Long driverId,
                             double lat,
                             double lng,
                             String mode) {

        String memberId = driverId.toString();

        switch (mode.toUpperCase()) {
            case "PACKAGE" -> geoOps()
                .add(GEO_KEY_PACKAGE,
                     new Point(lng, lat), memberId);
            case "PEOPLE" -> geoOps()
                .add(GEO_KEY_PEOPLE,
                     new Point(lng, lat), memberId);
            case "HYBRID" -> {
                geoOps().add(GEO_KEY_PACKAGE,
                             new Point(lng, lat), memberId);
                geoOps().add(GEO_KEY_PEOPLE,
                             new Point(lng, lat), memberId);
                geoOps().add(GEO_KEY_HYBRID,
                             new Point(lng, lat), memberId);
            }
        }

        redisTemplate.opsForValue()
            .set(DRIVER_STATUS + driverId,
                 "ONLINE", 10, TimeUnit.MINUTES);
        redisTemplate.opsForValue()
            .set(DRIVER_MODE + driverId,
                 mode.toUpperCase(), 10, TimeUnit.MINUTES);
    }

    // ─── Update driver GPS (called every 5 seconds) ───
    public void updateLocation(Long driverId,
                               double lat,
                               double lng) {

        String mode = getDriverMode(driverId);
        if (mode == null) return;

        String memberId = driverId.toString();

        switch (mode) {
            case "PACKAGE" -> geoOps()
                .add(GEO_KEY_PACKAGE,
                     new Point(lng, lat), memberId);
            case "PEOPLE" -> geoOps()
                .add(GEO_KEY_PEOPLE,
                     new Point(lng, lat), memberId);
            case "HYBRID" -> {
                geoOps().add(GEO_KEY_PACKAGE,
                             new Point(lng, lat), memberId);
                geoOps().add(GEO_KEY_PEOPLE,
                             new Point(lng, lat), memberId);
                geoOps().add(GEO_KEY_HYBRID,
                             new Point(lng, lat), memberId);
            }
        }

        redisTemplate.expire(
            DRIVER_STATUS + driverId, 10, TimeUnit.MINUTES);
    }

    // ─── Driver goes OFFLINE ──────────────────────────
    public void driverOffline(Long driverId) {
        String memberId = driverId.toString();

        geoOps().remove(GEO_KEY_PACKAGE, memberId);
        geoOps().remove(GEO_KEY_PEOPLE,  memberId);
        geoOps().remove(GEO_KEY_HYBRID,  memberId);

        redisTemplate.delete(DRIVER_STATUS + driverId);
        redisTemplate.delete(DRIVER_MODE   + driverId);
    }

    // ─── Find nearest drivers for LOGISTICS order ─────
    public List<Long> findNearestPackageDrivers(
            double lat, double lng, double radiusKm) {
        return searchNearby(
            GEO_KEY_PACKAGE, lat, lng, radiusKm);
    }

    // ─── Find nearest drivers for MOBILITY order ──────
    public List<Long> findNearestPeopleDrivers(
            double lat, double lng, double radiusKm) {
        return searchNearby(
            GEO_KEY_PEOPLE, lat, lng, radiusKm);
    }

    // ─── Core GeoSearch logic (Spring Data Redis 3.x) ─
    private List<Long> searchNearby(
            String geoKey,
            double lat, double lng,
            double radiusKm) {

        List<Long> driverIds = new ArrayList<>();

        try {
            GeoResults<RedisGeoCommands.GeoLocation<String>> results =
                geoOps().search(
                    geoKey,
                    GeoReference.fromCoordinate(
                        new Point(lng, lat)),
                    new Distance(radiusKm, Metrics.KILOMETERS),
                    RedisGeoCommands.GeoSearchCommandArgs
                        .newGeoSearchArgs()
                        .includeDistance()
                        .sortAscending()
                        .limit(10)
                );

            if (results != null) {
                results.getContent().forEach(result -> {
                    RedisGeoCommands.GeoLocation<String> location =
                        result.getContent();
                    if (location.getName() != null) {
                        driverIds.add(
                            Long.parseLong(location.getName()));
                    }
                });
            }

        } catch (Exception e) {
            System.err.println(
                "GeoSearch error: " + e.getMessage());
        }

        return driverIds;
    }

    // ─── Check if driver is online ────────────────────
    public boolean isDriverOnline(Long driverId) {
        return Boolean.TRUE.equals(
            redisTemplate.hasKey(DRIVER_STATUS + driverId));
    }

    // ─── Get driver current mode ──────────────────────
    public String getDriverMode(Long driverId) {
        Object mode = redisTemplate.opsForValue()
            .get(DRIVER_MODE + driverId);
        return mode != null ? mode.toString() : null;
    }
}