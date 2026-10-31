package com.bachnguyennn.align.server.web;

import java.net.URI;
import org.springframework.http.HttpStatus;

/**
 * Problem types (RFC 9457) used by the API. Each {@code type} URI points at its entry in
 * docs/agents/api-contracts.md.
 */
public enum ProblemType {
    MALFORMED_REQUEST("malformed-request", HttpStatus.BAD_REQUEST, "Malformed request"),
    INVALID_PARAMETER("invalid-parameter", HttpStatus.BAD_REQUEST, "Invalid parameter"),
    UNAUTHORIZED("unauthorized", HttpStatus.UNAUTHORIZED, "Missing or invalid bearer token"),
    FORBIDDEN("forbidden", HttpStatus.FORBIDDEN, "Forbidden"),
    NOT_FOUND("not-found", HttpStatus.NOT_FOUND, "Not found"),
    METHOD_NOT_ALLOWED("method-not-allowed", HttpStatus.METHOD_NOT_ALLOWED, "Method not allowed"),
    NOT_ACCEPTABLE("not-acceptable", HttpStatus.NOT_ACCEPTABLE, "Not acceptable"),
    CONFLICT("conflict", HttpStatus.CONFLICT, "Conflict"),
    PRECONDITION_FAILED("precondition-failed", HttpStatus.PRECONDITION_FAILED, "Precondition failed"),
    PAYLOAD_TOO_LARGE("payload-too-large", HttpStatus.PAYLOAD_TOO_LARGE, "Payload too large"),
    UNSUPPORTED_MEDIA_TYPE("unsupported-media-type", HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Unsupported media type"),
    VALIDATION_FAILED("validation-failed", HttpStatus.UNPROCESSABLE_ENTITY, "Validation failed"),
    LIMIT_EXCEEDED("limit-exceeded", HttpStatus.UNPROCESSABLE_ENTITY, "Limit exceeded"),
    PRECONDITION_REQUIRED("precondition-required", HttpStatus.PRECONDITION_REQUIRED, "Precondition required"),
    INTERNAL_ERROR("internal-error", HttpStatus.INTERNAL_SERVER_ERROR, "Internal server error");

    public static final String BASE_URI =
            "https://github.com/bachnguyennn/FixMySpine/blob/main/docs/agents/api-contracts.md#";

    private final String slug;
    private final HttpStatus status;
    private final String title;

    ProblemType(String slug, HttpStatus status, String title) {
        this.slug = slug;
        this.status = status;
        this.title = title;
    }

    public URI uri() {
        return URI.create(BASE_URI + slug);
    }

    public String slug() {
        return slug;
    }

    public HttpStatus status() {
        return status;
    }

    public String title() {
        return title;
    }

    /** The type used for a framework-generated error with this status. */
    public static ProblemType forStatus(int status) {
        return switch (status) {
            case 400 -> MALFORMED_REQUEST;
            case 401 -> UNAUTHORIZED;
            case 403 -> FORBIDDEN;
            case 404 -> NOT_FOUND;
            case 405 -> METHOD_NOT_ALLOWED;
            case 406 -> NOT_ACCEPTABLE;
            case 409 -> CONFLICT;
            case 412 -> PRECONDITION_FAILED;
            case 413 -> PAYLOAD_TOO_LARGE;
            case 415 -> UNSUPPORTED_MEDIA_TYPE;
            case 422 -> VALIDATION_FAILED;
            case 428 -> PRECONDITION_REQUIRED;
            default -> INTERNAL_ERROR;
        };
    }
}
