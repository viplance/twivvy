import { createApp } from "vue";
import App from "./App.vue";
import { i18n, localizeDocument } from "./i18n.ts";
import "../css/style.css";

localizeDocument();
createApp(App).use(i18n).mount("#app");
