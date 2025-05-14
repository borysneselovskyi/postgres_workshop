import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

public class ExplainTableBigInt {
    public static void main(String[] args) {
        // 1) check bind-value was provided
        if (args.length < 1) {
            System.err.println("Usage: java ExplainTableBigInt <bind_variable>");
            System.exit(1);
        }

        // 2) parse the bind value
        BigDecimal bindBig;
        int bindInt;
        try {
            bindBig = new BigDecimal(args[0]);
            bindInt = Integer.parseInt(args[0]);
        } catch (NumberFormatException e) {
            System.err.println("Invalid numeric value: " + args[0]);
            return;
        }

        // 3) read connection info from environment
        String host     = System.getenv("PGHOST");
        String port     = System.getenv("PGPORT");       // optional, default to 5432 if null
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
        System.out.println("Connecting to: " + url + " as user “" + user + "”");

        // 4) your EXPLAIN statement
        String sql = "EXPLAIN ANALYZE SELECT * FROM s1.tst_bind_bigint WHERE ext_id = ?";

        try (Connection conn = DriverManager.getConnection(url, user, password);
             PreparedStatement stmt = conn.prepareStatement(sql)) {

            System.out.println("Statement: " + sql);

            // First run with BigDecimal
            stmt.setBigDecimal(1, bindBig);
            System.out.println("Binding BigDecimal: " + bindBig);
            try (ResultSet rs = stmt.executeQuery()) {
                System.out.println("--- BEGIN OUTPUT (BigDecimal) ----");
                while (rs.next()) {
                    System.out.println(rs.getString(1));
                }
                System.out.println("--- END OUTPUT ------");
            }

            // Then run with int
            stmt.setInt(1, bindInt);
            System.out.println("Binding Integer: " + bindInt);
            try (ResultSet rs = stmt.executeQuery()) {
                System.out.println("--- BEGIN OUTPUT (Integer) ----");
                while (rs.next()) {
                    System.out.println(rs.getString(1));
                }
                System.out.println("--- END OUTPUT ------");
            }

        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }
}
