<!DOCTYPE html>
<html>
<body>

function MyButton() {
  return (
    <button>
      Do you want to check scams in your email?
    </button>
  );
}

export default function MyApp() {
  return (
    <div>
      <h1>Welcome to the Old People Safety app!</h1>
      <MyButton />
    </div>
  );
  
  if (confirm("Are you sure you want to proceed?")) {
  	console.log("User clicked yes.");
	} else {
  		console.log("User clicked no.");
	}
}

</body>
</html>
