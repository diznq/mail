function decodeUtfQStr(data_line, is_inline) {
    is_inline = is_inline || false;
    data_line = data_line.replace(/_/g, " ").replace(/\?=$/, "");
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
    element.textContent = content
        .replace(/=\?UTF-8\?Q\?(.*?)\?=/g, (full, match) => {
            return decodeUtfQStr(match);
        })
        .replace(/=\?UTF-8\?B\?(.*?)\?=/g, (full, match) => {
            return decodeURIComponent(atob(match).split('').map(function(c) {
                return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
            }).join(''))
        });
}

window.addEventListener("load", function() {
    decodeUtfQ(document.getElementById("title"));
    document.querySelectorAll(".mailbox .mails .mail .subject").forEach(subject => decodeUtfQ(subject));
})