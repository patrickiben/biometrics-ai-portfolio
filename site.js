/* Decorative sector codes for the toolkit home page. No operational status is implied. */
(function () {
  "use strict";
  // Sector codes on the home-page section modules.
  var codes = { ops: "OPS-01", bio: "BIO-02", mgmt: "MGT-03" };
  document.querySelectorAll(".sec").forEach(function (sec) {
    var cls = sec.classList.contains("ops") ? "ops"
            : sec.classList.contains("bio") ? "bio"
            : sec.classList.contains("mgmt") ? "mgmt" : null;
    var k = sec.querySelector(".k");
    if (cls && k && !k.querySelector(".code")) {
      var code = document.createElement("span");
      code.className = "code";
      code.textContent = codes[cls];
      k.appendChild(code);
    }
  });
})();
