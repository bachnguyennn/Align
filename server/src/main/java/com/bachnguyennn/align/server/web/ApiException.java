package com.bachnguyennn.align.server.web;

import java.util.List;

/** An error that maps directly to a problem+json response. */
public class ApiException extends RuntimeException {

    private final ProblemType type;
    private final List<FieldViolation> errors;

    public ApiException(ProblemType type, String detail) {
        this(type, detail, List.of());
    }

    public ApiException(ProblemType type, String detail, List<FieldViolation> errors) {
        super(detail, null, false, false);
        this.type = type;
        this.errors = List.copyOf(errors);
    }

    public ProblemType type() {
        return type;
    }

    public List<FieldViolation> errors() {
        return errors;
    }

    public static ApiException notFound(String detail) {
        return new ApiException(ProblemType.NOT_FOUND, detail);
    }

    public static ApiException invalidParameter(String detail) {
        return new ApiException(ProblemType.INVALID_PARAMETER, detail);
    }

    public static ApiException validation(List<FieldViolation> errors) {
        return new ApiException(ProblemType.VALIDATION_FAILED, "The request body has invalid fields.", errors);
    }
}
