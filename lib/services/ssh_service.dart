import 'package:dartssh2/dartssh2.dart';

class SshService {
  static Future<void> execute(
    String host,
    String password,
    String command,
  ) async {
    final socket = await SSHSocket.connect(
      host,
      22,
      timeout: const Duration(seconds: 10),
    );
    try {
      final client = SSHClient(
        socket,
        username: 'root',
        onPasswordRequest: () => password,
      );
      await client.authenticated;
      final session = await client.execute(command);
      await session.done;
      client.close();
      await client.done;
    } catch (e) {
      await socket.close();
      rethrow;
    }
  }
}
