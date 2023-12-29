window.addEventListener("load", function() {

    function serialize(obj) {
        var str = [];
        for(var p in obj)
            str.push(encodeURIComponent(p) + "=" + encodeURIComponent(obj[p]));
        return str.join("&");
    }

    /**
     * @type {HTMLFormElement}
     */
    const form = document.getElementById("form");
    form.onsubmit = (event) => {
        event.preventDefault();
        event.stopPropagation();

        const xhr = new XMLHttpRequest()

        xhr.responseType = "json";
        xhr.onload = (ev) => {
            if(xhr.status == 200) {
                location.href = "/mail/";
            } else {
                alert("Failed to send the e-mail: \n - " + xhr.response.errors.join("\n - "))
            }
        }
        xhr.onerror = (err) => {
            if(xhr.readyState == 4) {
                alert("Failed to send the e-mail: \n - " + xhr.response.errors.join("\n - "))
            } else {
                alert("Failed to send the request, please try again later")
            }
        }

        xhr.open("POST", form.action + "&j=1")
        xhr.setRequestHeader("Content-type", "application/x-url-encoded");
        xhr.send(serialize({
            to: document.getElementById("to").value,
            subject: document.getElementById("subject").value,
            body: document.getElementById("body").value,
            folder: document.getElementById("folder").value
        }))
    }
})