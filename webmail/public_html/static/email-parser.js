function parseEmail() {
    const raw = document.getElementById("email_raw").textContent;
    const parts = /boundary="(.*?)"/.exec(raw);
    let formats = ["raw"]
    let selected_format = "raw";
    if(parts && typeof(parts[1]) == "string") {
        const boundary = parts[1]
        const area = raw.split("--" + boundary + "--")[0].split("--" + boundary).map(a => a.trim())
        if(area.length > 1) {
            for(let i = 1; i < area.length; i++) {
                const data = area[i].replace(/\r/g, "")
                const rn = data.indexOf("\n\n")
                if(rn > -1) {
                    const type_line = data.substring(0, rn);
                    let data_line = data.substring(rn + 1);
                    let quoted_printable = type_line.match(/Content-Transfer-Encoding: quoted-printable/i);
                    if(quoted_printable) {
                        data_line = decodeUtfQStr(data_line)
                    }
                    const match = /content-type:([a-z/ ]+)/i.exec(type_line);
                    if(match && typeof(match[1]) == "string") {
                        const mime = match[1].trim();
                        if(mime == "text/plain") {
                            formats.push("text");
                            if(selected_format  == "raw") selected_format = "text";
                            document.getElementById("email_text").textContent = data_line.trim();
                        } else if(mime == "text/html") {
                            formats.push("html");
                            selected_format = "html";
                            document.getElementById("email_html").innerHTML = sanitize(data_line.trim()).innerHTML;
                        }
                    }
                }
            }
        }
    }
    document.getElementById("email_" + selected_format).style.display = "";
    formats.forEach(fmt => document.getElementById("ctl_" + fmt).style.display = "")
}

function setDisplayMode(type) {
    document.querySelectorAll("[data-email-view]").forEach(a => a.style.display = "none");
    document.getElementById("email_" + type).style.display ="";
}


window.addEventListener("load", function() {
    parseEmail();
})