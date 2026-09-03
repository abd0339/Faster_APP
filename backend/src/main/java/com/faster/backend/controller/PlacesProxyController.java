package com.faster.backend.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.Map;

/**
 * PlacesProxyController .
 *
 * The Google Places API key used to be shipped inside the Flutter
 * bundle (read from dotenv at runtime and passed into the search
 * widget). Anything in a web bundle is public: the key was readable
 * by anyone who opened DevTools, and usable to run up charges on
 * this project's Google billing account.
 *
 * Now Flutter calls THIS endpoint, and the server calls Google with
 * the key held server-side. The key never leaves the server, so it
 * cannot be extracted from the app at all.
 *
 * Authenticated on purpose: only signed-in users can search
 * addresses, so a scraper can't burn quota anonymously. HTTP
 * referrer restrictions in Google Cloud Console remain a useful
 * second layer.
 *
 * Responses are passed through unchanged so the existing Flutter
 * parsing logic keeps working — the only change on the client is
 * the URL it calls.
 */
@Slf4j
@RestController
@RequestMapping("/api/places")
@RequiredArgsConstructor
public class PlacesProxyController {

    private final RestTemplate restTemplate;

    @Value("${google.places.api-key:}")
    private String placesApiKey;

    private static final String AUTOCOMPLETE_URL =
            "https://maps.googleapis.com/maps/api/place/autocomplete/json";
    private static final String DETAILS_URL =
            "https://maps.googleapis.com/maps/api/place/details/json";

    // ─────────────────────────────────────────────────
    // GET /api/places/autocomplete?input=...&components=...
    // ─────────────────────────────────────────────────
    @GetMapping("/autocomplete")
    public ResponseEntity<?> autocomplete(
            @RequestParam String input,
            @RequestParam(required = false) String components,
            @RequestParam(required = false) String language) {

        if (placesApiKey.isBlank()) {
            log.error("google.places.api-key is not configured — "
                    + "address search will not work");
            return ResponseEntity.status(503).body(Map.of(
                    "status", "error",
                    "message", "Address search is temporarily unavailable"));
        }

        UriComponentsBuilder builder = UriComponentsBuilder
                .fromHttpUrl(AUTOCOMPLETE_URL)
                .queryParam("input", input)
                .queryParam("key", placesApiKey);

        // Defaults tuned for this app's market, overridable by the
        // caller (e.g. a merchant searching outside Lebanon).
        builder.queryParam("components",
                components != null ? components : "country:lb");
        builder.queryParam("language",
                language != null ? language : "en");

        try {
            Object body = restTemplate.getForObject(
                    builder.toUriString(), Object.class);
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            log.error("Places autocomplete failed: {}", e.getMessage());
            return ResponseEntity.status(502).body(Map.of(
                    "status", "error",
                    "message", "Address search failed. Please try again."));
        }
    }

    // ─────────────────────────────────────────────────
    // GET /api/places/details?placeId=...
    // ─────────────────────────────────────────────────
    @GetMapping("/details")
    public ResponseEntity<?> details(
            @RequestParam String placeId,
            @RequestParam(required = false) String fields) {

        if (placesApiKey.isBlank()) {
            return ResponseEntity.status(503).body(Map.of(
                    "status", "error",
                    "message", "Address lookup is temporarily unavailable"));
        }

        UriComponentsBuilder builder = UriComponentsBuilder
                .fromHttpUrl(DETAILS_URL)
                .queryParam("place_id", placeId)
                .queryParam("key", placesApiKey)
                // Only what the app actually uses — fewer fields also
                // means a cheaper Google billing tier.
                .queryParam("fields",
                        fields != null ? fields : "geometry,formatted_address");

        try {
            Object body = restTemplate.getForObject(
                    builder.toUriString(), Object.class);
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            log.error("Places details failed: {}", e.getMessage());
            return ResponseEntity.status(502).body(Map.of(
                    "status", "error",
                    "message", "Address lookup failed. Please try again."));
        }
    }
}