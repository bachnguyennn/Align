package com.bachnguyennn.align.server.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

/**
 * Device bearer tokens (D-018): 32 random bytes, base64url without padding (43 characters).
 * The server stores only the SHA-256 hash (hex); the token is shown to the client once.
 */
@Component
public class TokenService {

    public static final int TOKEN_BYTES = 32;
    public static final int TOKEN_LENGTH = 43;
    private static final Pattern TOKEN_PATTERN = Pattern.compile("[A-Za-z0-9_-]{" + TOKEN_LENGTH + "}");

    private final SecureRandom random = new SecureRandom();

    public String newToken() {
        byte[] bytes = new byte[TOKEN_BYTES];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    public boolean isWellFormed(String token) {
        return token != null && TOKEN_PATTERN.matcher(token).matches();
    }

    /** Lower-case hex SHA-256 of the token's ASCII bytes. */
    public String hash(String token) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(token.getBytes(StandardCharsets.US_ASCII)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is unavailable", e);
        }
    }

    /** Constant-time comparison of two hex hashes. */
    public boolean hashesEqual(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.US_ASCII), b.getBytes(StandardCharsets.US_ASCII));
    }
}
