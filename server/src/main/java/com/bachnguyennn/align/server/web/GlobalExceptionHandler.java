package com.bachnguyennn.align.server.web;

import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.lang.Nullable;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Turns every error into an RFC 9457 problem+json response with a type from {@link ProblemType}.
 * Details never echo request values (they may contain the user's data); exceptions are logged
 * by class and location only, never with their message.
 */
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ProblemDetail> handleApi(ApiException ex, HttpServletRequest request) {
        return problem(ex.type(), ex.getMessage(), ex.errors(), request);
    }

    @ExceptionHandler(RequestSizeLimitFilter.PayloadTooLargeException.class)
    public ResponseEntity<ProblemDetail> handleTooLarge(
            RequestSizeLimitFilter.PayloadTooLargeException ex, HttpServletRequest request) {
        return problem(ProblemType.PAYLOAD_TOO_LARGE, ex.getMessage(), List.of(), request);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ProblemDetail> handleTypeMismatch(MethodArgumentTypeMismatchException ex,
            HttpServletRequest request) {
        return problem(ProblemType.INVALID_PARAMETER, "Invalid value for parameter '" + ex.getName() + "'.",
                List.of(), request);
    }

    @ExceptionHandler({DataIntegrityViolationException.class, OptimisticLockingFailureException.class})
    public ResponseEntity<ProblemDetail> handleConcurrentWrite(RuntimeException ex, HttpServletRequest request) {
        log.info("Write conflict ({}) on {} {}", ex.getClass().getSimpleName(), request.getMethod(),
                request.getRequestURI());
        return problem(ProblemType.CONFLICT, "The request conflicts with a concurrent change. Retry it.",
                List.of(), request);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ProblemDetail> handleUnexpected(Exception ex, HttpServletRequest request) {
        StackTraceElement where = ex.getStackTrace().length > 0 ? ex.getStackTrace()[0] : null;
        log.error("Unhandled {} at {} on {} {}", ex.getClass().getName(), where, request.getMethod(),
                request.getRequestURI());
        return problem(ProblemType.INTERNAL_ERROR, "An unexpected error occurred.", List.of(), request);
    }

    @Override
    protected ResponseEntity<Object> handleMethodArgumentNotValid(MethodArgumentNotValidException ex,
            HttpHeaders headers, HttpStatusCode status, WebRequest request) {
        List<FieldViolation> errors = new ArrayList<>();
        ex.getBindingResult().getFieldErrors().forEach(error ->
                errors.add(new FieldViolation(error.getField(), error.getDefaultMessage())));
        ex.getBindingResult().getGlobalErrors().forEach(error ->
                errors.add(new FieldViolation("", error.getDefaultMessage())));
        errors.sort(Comparator.comparing(FieldViolation::field).thenComparing(FieldViolation::message));
        ProblemDetail body = Problems.of(ProblemType.VALIDATION_FAILED, "The request body has invalid fields.",
                errors, path(request));
        return asObject(body);
    }

    @Override
    protected ResponseEntity<Object> handleHttpMessageNotReadable(HttpMessageNotReadableException ex,
            HttpHeaders headers, HttpStatusCode status, WebRequest request) {
        for (Throwable cause = ex; cause != null; cause = cause.getCause()) {
            if (cause instanceof RequestSizeLimitFilter.PayloadTooLargeException tooLarge) {
                return asObject(Problems.of(ProblemType.PAYLOAD_TOO_LARGE, tooLarge.getMessage(), List.of(),
                        path(request)));
            }
        }
        String detail = "The request body is not valid JSON for this endpoint.";
        if (ex.getCause() instanceof UnrecognizedPropertyException unknown) {
            detail = "Unknown field '" + jsonPath(unknown) + "'.";
        } else if (ex.getCause() instanceof JsonMappingException mapping && !mapping.getPath().isEmpty()) {
            detail = "Invalid value or type for field '" + jsonPath(mapping) + "'.";
        } else if (ex.getCause() == null) {
            detail = "The request body is missing.";
        }
        return asObject(Problems.of(ProblemType.MALFORMED_REQUEST, detail, List.of(), path(request)));
    }

    @Override
    protected ResponseEntity<Object> handleMissingServletRequestParameter(
            MissingServletRequestParameterException ex, HttpHeaders headers, HttpStatusCode status,
            WebRequest request) {
        return asObject(Problems.of(ProblemType.INVALID_PARAMETER,
                "Missing query parameter '" + ex.getParameterName() + "'.", List.of(), path(request)));
    }

    @Override
    protected ResponseEntity<Object> handleServletRequestBindingException(
            org.springframework.web.bind.ServletRequestBindingException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        if (ex instanceof MissingRequestHeaderException missing) {
            return asObject(Problems.of(ProblemType.INVALID_PARAMETER,
                    "Missing header '" + missing.getHeaderName() + "'.", List.of(), path(request)));
        }
        return super.handleServletRequestBindingException(ex, headers, status, request);
    }

    /** Framework errors (404, 405, 406, 415, ...): keep the status, set our type and title. */
    @Override
    protected ResponseEntity<Object> createResponseEntity(@Nullable Object body, HttpHeaders headers,
            HttpStatusCode statusCode, WebRequest request) {
        ProblemDetail problem = body instanceof ProblemDetail existing ? existing : null;
        if (problem == null || problem.getType() == null || "about:blank".equals(problem.getType().toString())) {
            // Framework-generated: Spring's default details can quote request values, so replace
            // them with a fixed text per status.
            ProblemType type = ProblemType.forStatus(statusCode.value());
            problem = Problems.of(type, genericDetail(statusCode.value()), List.of(), path(request));
            problem.setStatus(statusCode.value());
        }
        HttpHeaders out = new HttpHeaders();
        out.addAll(headers);
        out.setContentType(MediaType.APPLICATION_PROBLEM_JSON);
        return new ResponseEntity<>(problem, out, statusCode);
    }

    private static String genericDetail(int status) {
        return switch (status) {
            case 404 -> "No such resource.";
            case 405 -> "This method is not supported for this resource.";
            case 406 -> "Only application/json responses are available.";
            case 415 -> "Send the request body as application/json.";
            case 400 -> "The request is malformed.";
            default -> "The request could not be processed.";
        };
    }

    private static String jsonPath(JsonMappingException ex) {
        StringBuilder path = new StringBuilder();
        for (JsonMappingException.Reference ref : ex.getPath()) {
            if (ref.getFieldName() != null) {
                if (!path.isEmpty()) {
                    path.append('.');
                }
                path.append(ref.getFieldName());
            } else if (ref.getIndex() >= 0) {
                path.append('[').append(ref.getIndex()).append(']');
            }
        }
        return path.toString();
    }

    private static ResponseEntity<ProblemDetail> problem(ProblemType type, String detail, List<FieldViolation> errors,
            HttpServletRequest request) {
        return ResponseEntity.status(type.status())
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(Problems.of(type, detail, errors, request.getRequestURI()));
    }

    private static ResponseEntity<Object> asObject(ProblemDetail body) {
        return ResponseEntity.status(body.getStatus())
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(body);
    }

    @Nullable
    private static String path(WebRequest request) {
        return request instanceof ServletWebRequest servlet ? servlet.getRequest().getRequestURI() : null;
    }
}
