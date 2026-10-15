package com.faster.backend.controller;

import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.PlacesRateLimitService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.List;
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
    private final PlacesRateLimitService placesRateLimitService;
    private final UserRepository userRepository;

    @Value("${google.places.api-key:}")
    private String placesApiKey;

    private static final String AUTOCOMPLETE_URL =
            "https://maps.googleapis.com/maps/api/place/autocomplete/json";
    private static final String DETAILS_URL =
            "https://maps.googleapis.com/maps/api/place/details/json";

    // §2.3 fix — below this, Google returns nothing useful anyway
    // and every call is billable; above this, it's not a real
    // address search anymore. Below MIN returns a Google-shaped
    // ZERO_RESULTS response so the existing Flutter parsing needs
    // no special case.
    private static final int MIN_INPUT_LENGTH = 3;
    private static final int MAX_INPUT_LENGTH = 200;

    // ─────────────────────────────────────────────────
    // GET /api/places/autocomplete?input=...&components=...
    // ─────────────────────────────────────────────────
    @GetMapping("/autocomplete")
    public ResponseEntity<?> autocomplete(
            @RequestParam String input,
            @RequestParam(required = false) String components,
            @RequestParam(required = false) String language,
            Authentication auth) {

        placesRateLimitService.checkAndRecord(getUserId(auth));

        if (placesApiKey.isBlank()) {
            log.error("google.places.api-key is not configured — "
                    + "address search will not work");
            return ResponseEntity.status(503).body(Map.of(
                    "status", "error",
                    "message", "Address search is temporarily unavailable"));
        }

        if (input == null || input.trim().length() < MIN_INPUT_LENGTH) {
            // Google-shaped response — no special case needed on
            // the Flutter side, and no billable call made.
            return ResponseEntity.ok(Map.of(
                    "predictions", List.of(),
                    "status", "ZERO_RESULTS"));
        }

        if (input.length() > MAX_INPUT_LENGTH) {
            return ResponseEntity.badRequest().body(Map.of(
                    "status", "error",
                    "message", "Search text is too long"));
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
                    buildUri(builder), Object.class);
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
            @RequestParam(required = false) String fields,
            Authentication auth) {

        placesRateLimitService.checkAndRecord(getUserId(auth));

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
                    buildUri(builder), Object.class);
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            log.error("Places details failed: {}", e.getMessage());
            return ResponseEntity.status(502).body(Map.of(
                    "status", "error",
                    "message", "Address lookup failed. Please try again."));
        }
    }

    // §2.3 fix — two bugs in one: (1) UriComponentsBuilder does NOT
    // percent-encode query values unless encode() is called, so an
    // address like "Rue 5 & 6" produced "...?input=Rue 5 & 6&key=...",
    // letting Google (or an attacker) read "6" as a separate query
    // param; (2) RestTemplate treats a String url as a URI TEMPLATE,
    // so any literal '{' or '}' the user typed was read as a
    // placeholder and threw IllegalArgumentException. Returning a
    // java.net.URI skips template expansion entirely, and encode()
    // fixes the query string.
    private URI buildUri(UriComponentsBuilder builder) {
        return builder.encode().build().toUri();
    }

    // §2.4 fix — resolves the authenticated caller for the per-user
    // Places spend cap. Returns null (never blocks) if the principal
    // can't be resolved — the endpoint is already authenticated, so
    // this is belt-and-braces, not the primary guard.
    private Long getUserId(Authentication auth) {
        if (auth == null) return null;
        String principal = auth.getName();
        return userRepository.findByEmail(principal)
                .or(() -> userRepository.findByPhone(principal))
                .map(User::getId)
                .orElse(null);
    }
}