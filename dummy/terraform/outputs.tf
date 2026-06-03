output "pet_name" {
  value       = random_pet.name.id
  description = "The generated pet name."
}

output "artifact_path" {
  value       = local_file.artifact.filename
  description = "Path of the generated local artifact file."
}
