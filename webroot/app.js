// Bridge to execute shell commands
const exec = (cmd) => {
    if (window.ksu) {
        return window.ksu.exec(cmd);
    } else if (window.webui) {
        return window.webui.exec(cmd);
    } else {
        console.warn('KernelSU/WebUI bridge not found. Mocking exec:', cmd);
        return Promise.resolve({ errno: 0, stdout: 'mocked output', stderr: '' });
    }
};

const MODDIR = '/data/adb/modules/tproxy_bridge';
const CORE_SH = `sh ${MODDIR}/scripts/core.sh`;
const CONFIG_JSON = `${MODDIR}/config/config.json`;
const LOG_FILE = `${MODDIR}/logs/tproxy.log`;

const state = {
    config: {},
    status: 'stopped'
};

const updateStatus = async () => {
    const { stdout } = await exec(`${CORE_SH} status`);
    state.status = stdout.trim();
    const badge = document.getElementById('status-badge');
    badge.textContent = state.status;
    badge.className = `badge ${state.status}`;
};

const loadConfig = async () => {
    const { stdout } = await exec(`cat ${CONFIG_JSON}`);
    try {
        state.config = JSON.parse(stdout);
        fillForm();
    } catch (e) {
        console.error('Failed to parse config:', e);
    }
};

const fillForm = () => {
    const form = document.getElementById('config-form');
    document.getElementById('enabled').checked = state.config.enabled;
    document.getElementById('mode').value = state.config.mode;
    document.getElementById('upstream-type').value = state.config.upstream.type;
    document.getElementById('upstream-host').value = state.config.upstream.host;
    document.getElementById('upstream-port').value = state.config.upstream.port;
    document.getElementById('upstream-username').value = state.config.upstream.username;
    document.getElementById('upstream-password').value = state.config.upstream.password;
    document.getElementById('upstream-udp').checked = state.config.upstream.udp;
};

const saveConfig = async (e) => {
    e.preventDefault();
    const newConfig = {
        ...state.config,
        enabled: document.getElementById('enabled').checked,
        mode: document.getElementById('mode').value,
        upstream: {
            type: document.getElementById('upstream-type').value,
            host: document.getElementById('upstream-host').value,
            port: parseInt(document.getElementById('upstream-port').value),
            username: document.getElementById('upstream-username').value,
            password: document.getElementById('upstream-password').value,
            udp: document.getElementById('upstream-udp').checked
        }
    };

    const configStr = JSON.stringify(newConfig, null, 2);
    // Escape single quotes for shell
    const escapedConfig = configStr.replace(/'/g, "'\\''");
    await exec(`echo '${escapedConfig}' > ${CONFIG_JSON}`);
    state.config = newConfig;
    alert('Settings saved!');
};

const refreshLogs = async () => {
    const { stdout } = await exec(`tail -n 100 ${LOG_FILE}`);
    document.getElementById('log-viewer').textContent = stdout || 'No logs yet.';
};

// Event Listeners
document.getElementById('btn-start').onclick = async () => {
    await exec(`${CORE_SH} start`);
    updateStatus();
};

document.getElementById('btn-stop').onclick = async () => {
    await exec(`${CORE_SH} stop`);
    updateStatus();
};

document.getElementById('btn-restart').onclick = async () => {
    await exec(`${CORE_SH} restart`);
    updateStatus();
};

document.getElementById('btn-refresh-logs').onclick = refreshLogs;

document.getElementById('config-form').onsubmit = saveConfig;

// Initialize
window.onload = () => {
    updateStatus();
    loadConfig();
    refreshLogs();
    setInterval(updateStatus, 5000);
};
