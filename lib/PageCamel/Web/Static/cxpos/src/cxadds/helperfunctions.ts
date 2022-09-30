export function openImageFileDialog(fileInputID: string, callback: (file: null | ArrayBuffer | string) => void) {
    //select the file input element
    var fileInput = document.getElementById(fileInputID) as HTMLInputElement;
    //add a change listener
    fileInput.addEventListener('change', function () {
        //read the file and check if it is a valid image
        var fr = new FileReader();
        fr.onload = function () {
            var bgimage: string = fr.result?.toString() || "";
            //check if image is valid
            var img = new Image();
            img.onload = function () {
                console.log("image is valid");
                callback(bgimage);
            }
            img.onerror = function () {
                console.log("image is not valid");
                return; //invalid image
            };
            img.src = bgimage;
            fileInput.value = ""; //prevents caching of the image
        }
        console.log('File Reader:', fr)
        fr.readAsDataURL(fileInput.files![0]);
        fileInput.removeEventListener('change', function () { });
    });
    //trigger the click event
    fileInput.click();
}