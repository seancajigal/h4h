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
      <h1>Welcome to the EmailScams app!</h1>
      <MyButton />
    </div>
  );
  
  if (confirm("Are you sure you want to proceed?")) {
  	console.log("User clicked yes.");
	} else {
  		console.log("User clicked no.");
	}
}
