import Bonjour from 'bonjour-service';
import qrcode from 'qrcode-terminal';
import os from 'node:os';
import path from 'node:path';

export class Discovery {
  constructor({ port, code, salt, shell, host = '0.0.0.0', noQr = false, noBonjour = false }) {
    this.port = port;
    this.code = code;
    this.salt = salt;
    this.shell = path.basename(shell);
    this.host = host;
    this.noQr = noQr;
    this.noBonjour = noBonjour;
    this.bonjour = null;
    this.service = null;
  }

  start() {
    const ip = this._getLocalIp();
    const params = this.code ? `?code=${this.code}&salt=${this.salt}` : '';
    const url = `ws://${ip}:${this.port}${params}`;

    if (!this.noBonjour) {
      this.bonjour = new Bonjour();
      this.service = this.bonjour.publish({
        name: `terminal-thingy-${os.hostname()}`,
        type: 'terminal-thingy',
        port: this.port,
        txt: {
          salt: this.salt || '',
          shell: this.shell,
          hostname: os.hostname(),
          ip: ip,
          port: String(this.port),
        },
      });
    }

    return { ip, url };
  }

  printConnectionInfo(url, code) {
    console.log('');
    console.log('🔗 terminal-thingy streaming on local network');
    console.log('');

    if (!this.noQr) {
      qrcode.generate(url, { small: true }, (qr) => {
        const lines = qr.split('\n');
        const infoLines = code
          ? [`    PIN: ${code.slice(0, 3)} ${code.slice(3)}`, '', '    Scan QR or enter PIN in the app']
          : ['    No auth — open to local network', '', '    Scan QR to connect'];
        for (let i = 0; i < Math.max(lines.length, infoLines.length); i++) {
          const qrLine = lines[i] || '';
          const infoLine = infoLines[i - 1] || '';
          console.log(`  ${qrLine.padEnd(30)}${infoLine}`);
        }
        console.log('');
        console.log('  Waiting for connections...');
        console.log('');
      });
    } else {
      if (code) console.log(`  PIN: ${code.slice(0, 3)} ${code.slice(3)}`);
      console.log(`  URL: ${url}`);
      console.log('');
      console.log('  Waiting for connections...');
      console.log('');
    }
  }

  _getLocalIp() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
      for (const iface of interfaces[name]) {
        if (iface.family === 'IPv4' && !iface.internal) {
          return iface.address;
        }
      }
    }
    return '127.0.0.1';
  }

  stop() {
    if (this.service) {
      this.service.stop();
      this.service = null;
    }
    if (this.bonjour) {
      this.bonjour.destroy();
      this.bonjour = null;
    }
  }
}
