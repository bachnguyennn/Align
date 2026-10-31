package com.bachnguyennn.align.server.summary;

import com.bachnguyennn.align.server.auth.DevicePrincipal;
import com.bachnguyennn.align.server.summary.SummaryService.SummaryResponse;
import com.bachnguyennn.align.server.web.ApiException;
import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.regex.Pattern;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v1/analytics", produces = MediaType.APPLICATION_JSON_VALUE)
public class SummaryController {

    /** IANA region ids (Europe/Berlin, America/Argentina/Buenos_Aires) or UTC. */
    private static final Pattern ZONE_ID = Pattern.compile("UTC|[A-Za-z][A-Za-z0-9_+-]{0,40}(/[A-Za-z0-9_+-]{1,40}){1,2}");

    private final SummaryService service;

    public SummaryController(SummaryService service) {
        this.service = service;
    }

    @GetMapping("/summary")
    public SummaryResponse summary(@AuthenticationPrincipal DevicePrincipal device,
            @RequestParam("from") String from, @RequestParam("to") String to, @RequestParam("tz") String tz) {
        return service.summarize(device.deviceId(), parseDate("from", from), parseDate("to", to), parseZone(tz));
    }

    private static LocalDate parseDate(String name, String value) {
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException e) {
            throw ApiException.invalidParameter("Parameter '" + name + "' must be a date such as 2026-10-31.");
        }
    }

    private static ZoneId parseZone(String value) {
        if (value.length() <= 64 && ZONE_ID.matcher(value).matches()) {
            try {
                return ZoneId.of(value);
            } catch (DateTimeException e) {
                // fall through
            }
        }
        throw ApiException.invalidParameter("Parameter 'tz' must be an IANA time zone such as Europe/Berlin.");
    }
}
