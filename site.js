/* Mission-control live touches for the AI-for-Biometrics site: a UTC mission clock,
   an "all sectors nominal" status readout in the command bar, and sector codes on the
   home-page modules. Pure enhancement — the pages read fine without it. */
(function () {
  "use strict";
  var top = document.querySelector(".top");
  if (top && !top.querySelector(".mc-status")) {
    var status = document.createElement("span");
    status.className = "mc-status";
    status.innerHTML = '<span class="dot"></span> All sectors nominal';
    var clock = document.createElement("span");
    clock.className = "mc-clock";
    top.appendChild(status);
    top.appendChild(clock);
    var pad = function (n) { return String(n).padStart(2, "0"); };
    var tick = function () {
      var d = new Date();
      clock.textContent = pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + ":" + pad(d.getUTCSeconds()) + " UTC";
    };
    tick();
    setInterval(tick, 1000);
  }
  // sector codes + ONLINE status on the home-page section modules
  var codes = { ops: "OPS-01", bio: "BIO-02", mgmt: "MGT-03" };
  document.querySelectorAll(".sec").forEach(function (sec) {
    var cls = sec.classList.contains("ops") ? "ops"
            : sec.classList.contains("bio") ? "bio"
            : sec.classList.contains("mgmt") ? "mgmt" : null;
    var k = sec.querySelector(".k");
    if (cls && k && !k.querySelector(".code")) {
      var code = document.createElement("span");
      code.className = "code";
      code.textContent = codes[cls] + " · ONLINE";
      k.appendChild(code);
    }
  });
})();
