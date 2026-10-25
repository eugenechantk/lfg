// Safari runs this in the source page before launching the share extension.
// Keep selection and URL separate; the title belongs only in the preview.
var LFGSharePreprocessor = function() {};
LFGSharePreprocessor.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            url: document.URL,
            title: document.title,
            selection: String(window.getSelection() || "")
        });
    }
};
var ExtensionPreprocessingJS = new LFGSharePreprocessor;
