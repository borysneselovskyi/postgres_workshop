import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;

public class TableAccess {
    public static void main(String[] args) {
        // 1) check bind-value was provided
        if (args.length < 1) {
            System.err.println("Usage: java TableAccess <bind_variable>");
            System.exit(1);
        }

        // 2) parse the bind value
        BigDecimal bindBig;
        try {
            bindBig = new BigDecimal(args[0]);
        } catch (NumberFormatException e) {
            System.err.println("Invalid numeric value: " + args[0]);
            return;
        }

        // 3) read connection info from environment
        String host     = System.getenv("PGHOST");
        String port     = System.getenv("PGPORT");       // optional
        String dbName   = System.getenv("PGDATABASE");
        String user     = System.getenv("PGUSER");
        String password = System.getenv("PGPASSWORD");

        if (host == null || dbName == null || user == null || password == null) {
            System.err.println("Please set PGHOST, PGDATABASE, PGUSER and PGPASSWORD environment variables.");
            System.exit(2);
        }
        if (port == null) {
            port = "5432";
        }

        String url = String.format("jdbc:postgresql://%s:%s/%s", host, port, dbName);
        System.out.println("Connecting to: " + url + " as user \"" + user + "\"");

        String sql = "SELECT * FROM s1.tst_bind_bigint WHERE ext_id = ?";

        try (Connection conn = DriverManager.getConnection(url, user, password);
             PreparedStatement stmt = conn.prepareStatement(sql)) {

            // bind the parameter
            stmt.setBigDecimal(1, bindBig);
            System.out.println("Statement: " + sql);
            System.out.println("Binding Variable: " + bindBig);

            // measure just the query execution
            long startNanos = System.nanoTime();
            try (ResultSet rs = stmt.executeQuery()) {
                long elapsedNanos = System.nanoTime() - startNanos;
                double elapsedMs = elapsedNanos / 1_000_000.0;
                System.out.printf("Query executed in %.3f ms%n", elapsedMs);

                // print all columns for each row
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                System.out.println("--- BEGIN OUTPUT ----");
                while (rs.next()) {
                    StringBuilder row = new StringBuilder();
                    for (int i = 1; i <= columnCount; i++) {
                        String colName = meta.getColumnLabel(i);
                        Object value   = rs.getObject(i);
                        row.append(colName)
                           .append("=")
                           .append(value);
                        if (i < columnCount) {
                            row.append(", ");
                        }
                    }
                    System.out.println(row);
                }
                System.out.println("--- END OUTPUT ------");
            }

        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }
}

