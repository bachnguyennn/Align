package com.bachnguyennn.align.reference;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.io.PrintStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Recomputes the {@code reference} block of committed fixtures with the current reference
 * pipeline and rewrites only that block; samples, {@code expected} and every other field are left
 * byte for byte as they are. A block whose content (ignoring {@code producedBy}) is unchanged is not
 * touched, so fixtures written by the Python generator keep {@code producedBy: align_reference}.
 *
 * <pre>
 *   ./mvnw -q compile exec:java@rereference                          # rewrite changed blocks
 *   ./mvnw -q compile exec:java@rereference -Dexec.args="--check"    # only report; exit 1 if any differ
 * </pre>
 * Options: {@code --check}, {@code --dir <fixture dir>} (default shared/fixtures/motion).
 */
public final class Rereference {

    private Rereference() {}

    /** One fixture whose stored reference differs from the recomputed one. */
    public record Change(Path path, List<String> fields) {}

    /** Top-level reference fields that differ (ignoring {@code producedBy}). */
    public static List<String> differingFields(JsonNode stored, JsonNode computed) {
        List<String> fields = new ArrayList<>();
        for (Map.Entry<String, JsonNode> e : computed.properties()) {
            if (e.getKey().equals("producedBy")) {
                continue;
            }
            JsonNode old = stored != null ? stored.get(e.getKey()) : null;
            if (old == null || !old.equals(e.getValue())) {
                fields.add(e.getKey());
            }
        }
        if (stored != null) {
            for (Map.Entry<String, JsonNode> e : stored.properties()) {
                if (!e.getKey().equals("producedBy") && !computed.has(e.getKey())) {
                    fields.add(e.getKey() + " (removed)");
                }
            }
        }
        return fields;
    }

    /** Recomputes every fixture in {@code directory}; rewrites changed ones unless {@code checkOnly}. */
    public static List<Change> run(Path directory, boolean checkOnly) {
        List<Change> changes = new ArrayList<>();
        for (Path path : Fixtures.fixturePaths(directory)) {
            try {
                String text = Files.readString(path, StandardCharsets.UTF_8);
                ObjectNode fx = (ObjectNode) Json.parse(text);
                if (!fx.has("reference")) {
                    continue;
                }
                ObjectNode computed = Fixtures.referenceBlock(Fixtures.replay(fx));
                List<String> fields = differingFields(fx.get("reference"), computed);
                if (fields.isEmpty()) {
                    continue;
                }
                changes.add(new Change(path, fields));
                if (!checkOnly) {
                    fx.set("reference", computed);  // replaces in place, keeping the key order
                    Files.writeString(path, Generator.dumpsFixture(fx), StandardCharsets.UTF_8);
                }
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }
        return changes;
    }

    /** Runs the CLI, printing to {@code out}; returns the exit status. */
    public static int run(String[] args, PrintStream out) {
        boolean check = false;
        Path dir = null;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--check" -> check = true;
                case "--dir" -> dir = Path.of(args[++i]);
                case "-h", "--help" -> {
                    out.println("usage: Rereference [--check] [--dir <fixture dir>]");
                    return 0;
                }
                default -> throw new IllegalArgumentException("unknown argument: " + args[i]);
            }
        }
        if (dir == null) {
            dir = Fixtures.fixtureDir();
        }
        List<Change> changes = run(dir, check);
        for (Change c : changes) {
            out.println((check ? "differs:   " : "rewritten: ") + c.path().getFileName() + " " + c.fields());
        }
        out.println(changes.size() + " reference block(s) " + (check ? "differ" : "rewritten"));
        return check && !changes.isEmpty() ? 1 : 0;
    }

    public static void main(String[] args) {
        int status = run(args, System.out);
        if (status != 0) {
            System.exit(status);
        }
    }
}
