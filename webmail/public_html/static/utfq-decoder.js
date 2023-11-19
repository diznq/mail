function decodeUtfQStr(data_line, is_inline) {
    is_inline = is_inline || false;
    if(is_inline) data_line = data_line.replace(/_/g, " ").replace(/\?=$/, "");
    data_line = data_line.replace(/=\n/g, "");
    data_line = data_line.replace(/(=[0-9A-F=\r\n]{2,})/g, (full) => {
        const parts = full.split("=");
        const ok = parts.filter(a => {
            const sanitized = a.replace(/[\r\n]/g, "");
            return sanitized.length == 2 && sanitized.match(/[0-9A-F]{2}/)
        }).length > 0;
        if(!ok) {
            return decodeURIComponent(full.replace("=", "%"));
        }
        const clean = full.replace(/[\r\n]/g, "").replace(/==/g, "=");
        const decoded = decodeURIComponent(clean.replace(/=/g, "%"));
        return decoded;
    })
    return data_line;
}

function decodeUtfQ(element) {
    if(!element) return;
    const content = element.textContent;
    if(content.indexOf("=?UTF-8?Q?") == 0) {
        element.textContent = decodeUtfQStr(content.substring("=?UTF-8?Q?".length), true)
    }
}

window.addEventListener("load", function() {
    decodeUtfQ(document.getElementById("title"));
    document.querySelectorAll(".mailbox .mails .mail .subject").forEach(subject => decodeUtfQ(subject));
})