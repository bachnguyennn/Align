package com.bachnguyennn.align.reference;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

/**
 * JSON reading (Jackson tree model, the Java counterpart of Python's dicts) and writing in exactly
 * the layout of Python's {@code json.dumps}: {@link #dumps(JsonNode, int)} = {@code indent=n} and
 * {@link #dumpsCompact(JsonNode)} = {@code separators=(",", ":")}, with Python float repr and
 * {@code ensure_ascii}. Integers and floats stay distinct (IntNode vs DoubleNode), like Python.
 */
public final class Json {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    public static final JsonNodeFactory NODES = JsonNodeFactory.instance;

    private Json() {}

    public static ObjectNode object() {
        return NODES.objectNode();
    }

    public static ArrayNode array() {
        return NODES.arrayNode();
    }

    public static ArrayNode array(double... values) {
        ArrayNode a = NODES.arrayNode();
        for (double v : values) {
            a.add(v);
        }
        return a;
    }

    public static JsonNode parse(String text) {
        try {
            return MAPPER.readTree(text);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public static ObjectNode load(Path path) {
        try {
            return (ObjectNode) MAPPER.readTree(Files.readString(path));
        } catch (IOException e) {
            throw new UncheckedIOException("cannot read " + path, e);
        }
    }

    /** {@code json.dumps(node, indent=indent)}. */
    public static String dumps(JsonNode node, int indent) {
        StringBuilder sb = new StringBuilder();
        write(sb, node, " ".repeat(indent), 0);
        return sb.toString();
    }

    /** {@code json.dumps(node, separators=(",", ":"))}. */
    public static String dumpsCompact(JsonNode node) {
        StringBuilder sb = new StringBuilder();
        write(sb, node, null, 0);
        return sb.toString();
    }

    private static void write(StringBuilder sb, JsonNode node, String indent, int level) {
        switch (node.getNodeType()) {
            case OBJECT -> {
                if (node.isEmpty()) {
                    sb.append("{}");
                    return;
                }
                sb.append('{');
                boolean first = true;
                for (Map.Entry<String, JsonNode> e : node.properties()) {
                    if (!first) {
                        sb.append(',');
                    }
                    first = false;
                    newline(sb, indent, level + 1);
                    writeString(sb, e.getKey());
                    sb.append(indent == null ? ":" : ": ");
                    write(sb, e.getValue(), indent, level + 1);
                }
                newline(sb, indent, level);
                sb.append('}');
            }
            case ARRAY -> {
                if (node.isEmpty()) {
                    sb.append("[]");
                    return;
                }
                sb.append('[');
                for (int i = 0; i < node.size(); i++) {
                    if (i > 0) {
                        sb.append(',');
                    }
                    newline(sb, indent, level + 1);
                    write(sb, node.get(i), indent, level + 1);
                }
                newline(sb, indent, level);
                sb.append(']');
            }
            case STRING -> writeString(sb, node.textValue());
            case BOOLEAN -> sb.append(node.booleanValue() ? "true" : "false");
            case NULL -> sb.append("null");
            case NUMBER -> {
                if (node.isIntegralNumber()) {
                    sb.append(node.bigIntegerValue());
                } else {
                    sb.append(PythonFormat.repr(node.doubleValue()));
                }
            }
            default -> throw new IllegalArgumentException("unsupported JSON node: " + node.getNodeType());
        }
    }

    private static void newline(StringBuilder sb, String indent, int level) {
        if (indent != null) {
            sb.append('\n').append(indent.repeat(level));
        }
    }

    /** Python's {@code ensure_ascii} string encoding. */
    private static void writeString(StringBuilder sb, String s) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                case '\b' -> sb.append("\\b");
                case '\f' -> sb.append("\\f");
                default -> {
                    if (c < 0x20 || c > 0x7e) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
    }
}
