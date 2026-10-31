package com.bachnguyennn.align.server;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

class SettingsApiTest extends ApiTestSupport {

    private ResultActions putSettings(Device device, String ifMatch, Object settings) throws Exception {
        var request = put("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("settings", settings)));
        if (ifMatch != null) {
            request.header(HttpHeaders.IF_MATCH, ifMatch);
        }
        return mvc.perform(request);
    }

    private static Map<String, Object> sample() {
        Map<String, Object> configuration = new LinkedHashMap<>();
        configuration.put("forwardThresholdDegrees", 12.0);
        configuration.put("backwardThresholdDegrees", 17.0);
        configuration.put("lateralThresholdDegrees", 12.0);
        configuration.put("sustainedDuration", 20.0);
        configuration.put("reminderCooldown", 600.0);
        configuration.put("minimumCalibrationSamples", 100);
        Map<String, Object> settings = new LinkedHashMap<>();
        settings.put("remindersEnabled", true);
        settings.put("soundEnabled", false);
        settings.put("hapticsEnabled", true);
        settings.put("demoModeEnabled", false);
        settings.put("configuration", configuration);
        return settings;
    }

    @Test
    void emptyDocumentHasVersionZero() throws Exception {
        Device device = register();
        getAs(device, "/api/v1/settings")
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"0\""))
                .andExpect(jsonPath("$.version").value(0))
                .andExpect(jsonPath("$.updatedAt").isEmpty())
                .andExpect(jsonPath("$.settings").isMap())
                .andExpect(jsonPath("$.settings.remindersEnabled").doesNotExist());
    }

    @Test
    void writesAdvanceTheVersionAndStaleWritesFail() throws Exception {
        Device device = register();
        putSettings(device, "\"0\"", sample())
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"1\""))
                .andExpect(jsonPath("$.version").value(1))
                .andExpect(jsonPath("$.updatedAt").isString())
                .andExpect(jsonPath("$.settings.soundEnabled").value(false))
                .andExpect(jsonPath("$.settings.configuration.forwardThresholdDegrees").value(12.0))
                .andExpect(jsonPath("$.settings.configuration.minimumCalibrationSamples").value(100));

        // A second client that still holds version 0 loses: 412, the document is unchanged.
        putSettings(device, "\"0\"", Map.of("soundEnabled", true)).andExpect(problem(412, "precondition-failed"));
        getAs(device, "/api/v1/settings")
                .andExpect(header().string(HttpHeaders.ETAG, "\"1\""))
                .andExpect(jsonPath("$.settings.soundEnabled").value(false));

        // With the current version it succeeds; the whole document is replaced.
        putSettings(device, "\"1\"", Map.of("soundEnabled", true))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value(2))
                .andExpect(jsonPath("$.settings.soundEnabled").value(true))
                .andExpect(jsonPath("$.settings.configuration").doesNotExist());

        // A version from the future also fails.
        putSettings(device, "\"7\"", sample()).andExpect(problem(412, "precondition-failed"));
    }

    @Test
    void identicalWriteKeepsTheVersion() throws Exception {
        Device device = register();
        putSettings(device, "\"0\"", sample()).andExpect(jsonPath("$.version").value(1));
        putSettings(device, "\"1\"", sample())
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"1\""))
                .andExpect(jsonPath("$.version").value(1));
    }

    @Test
    void wildcardMatchesOnlyAnExistingDocument() throws Exception {
        Device device = register();
        putSettings(device, "*", sample()).andExpect(problem(412, "precondition-failed"));
        putSettings(device, "\"0\"", sample()).andExpect(status().isOk());
        putSettings(device, "*", Map.of("demoModeEnabled", true))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value(2));
    }

    @Test
    void ifMatchIsRequired() throws Exception {
        Device device = register();
        putSettings(device, null, sample()).andExpect(problem(428, "precondition-required"));
    }

    @ParameterizedTest(name = "If-Match: {0}")
    @ValueSource(strings = {"0", "W/\"0\"", "\"abc\"", "\"-1\""})
    void malformedOrWeakIfMatchNeverMatches(String ifMatch) throws Exception {
        Device device = register();
        putSettings(device, ifMatch, sample()).andExpect(problem(412, "precondition-failed"));
    }

    @Test
    void getHonoursIfNoneMatch() throws Exception {
        Device device = register();
        putSettings(device, "\"0\"", sample()).andExpect(status().isOk());
        mvc.perform(get("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .header(HttpHeaders.IF_NONE_MATCH, "\"1\""))
                .andExpect(status().isNotModified());
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {
            "{\"settings\":{\"configuration\":{\"forwardThresholdDegrees\":0.5}}}",
            "{\"settings\":{\"configuration\":{\"forwardThresholdDegrees\":120}}}",
            "{\"settings\":{\"configuration\":{\"sustainedDuration\":0}}}",
            "{\"settings\":{\"configuration\":{\"reminderCooldown\":-1}}}",
            "{\"settings\":{\"configuration\":{\"calibrationSpreadQuantile\":1.5}}}",
            "{\"settings\":{\"configuration\":{\"minimumCalibrationSamples\":0}}}",
            "{\"settings\":null}",
            "{}"})
    void outOfRangeValuesAre422(String raw) throws Exception {
        Device device = register();
        mvc.perform(put("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .header(HttpHeaders.IF_MATCH, "\"0\"").contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(problem(422, "validation-failed"))
                .andExpect(jsonPath("$.errors[0].field").isString());
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {
            // axes and the calibration baseline are deliberately not part of the synced document.
            "{\"settings\":{\"configuration\":{\"axes\":{\"forwardAxis\":{\"x\":-1,\"y\":0,\"z\":0}}}}}",
            "{\"settings\":{\"baseline\":{\"gravity\":{\"x\":0,\"y\":0,\"z\":-1}}}}",
            "{\"settings\":{\"soundEnabled\":\"yes\"}}",
            "{\"settings\":{\"soundEnabled\":1}}",
            "{\"settings\":{\"configuration\":{\"minimumCalibrationSamples\":1.5}}}"})
    void unknownFieldsAndWrongTypesAre400(String raw) throws Exception {
        Device device = register();
        mvc.perform(put("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .header(HttpHeaders.IF_MATCH, "\"0\"").contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(problem(400, "malformed-request"));
    }
}
