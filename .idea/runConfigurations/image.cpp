#include <opencv2/opencv.hpp>
using namespace std;

int main() {
    mat image = imread("disabled_people.png");

    if (image.empty()) {
        printf("Could not open or find the image\n");
        return -1;
    }

    namedWindow("Disabled People Program", WINDOW_AUTOSIZE);

    imshow("Disabled People Program", image);

    return 0;
}
